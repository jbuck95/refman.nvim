---@tag refman.csl
---Formats citations using Citation Style Language (CSL) via citation-js.
---Requires: npm install -g @citation-js/core @citation-js/plugin-csl
local M = {}

local log = require("refman.log")

-- ── npm / node helpers ───────────────────────────────────────────────────────

local npm_root = nil

local function get_npm_root()
  if npm_root then
    return npm_root
  end
  local plugin_root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h")
  local local_nm = plugin_root .. "/node_modules"
  if vim.fn.isdirectory(local_nm) == 1 then
    npm_root = local_nm
    return npm_root
  end
  local f = io.popen("npm root -g 2>/dev/null")
  if f then
    npm_root = f:read("*l"):gsub("%s+$", "")
    f:close()
  end
  return npm_root
end

local function node_cmd(script)
  local tmp = os.tmpname()
  local f = io.open(tmp, "w")
  f:write(script)
  f:close()
  local prefix = ""
  local root = get_npm_root()
  if root and root ~= "" then
    prefix = "NODE_PATH=" .. root .. " "
  end
  local cmd = prefix .. "node " .. tmp .. " 2>/dev/null; rm -f " .. tmp
  return cmd
end

local function run_csl(csl_json_array, style_path, lang, format_type)
  format_type = format_type or "bibliography"
  lang = lang or "de-DE"

  local json_file = os.tmpname()
  local f = io.open(json_file, "w")
  f:write(vim.json.encode(csl_json_array))
  f:close()

  local output_file = os.tmpname()

  local script = string.format([[
const fs = require('fs');
const { Cite } = require('@citation-js/core');
require('@citation-js/plugin-csl');
const raw = fs.readFileSync('%s', 'utf8');
const data = JSON.parse(raw);
const cite = new Cite(data);
const result = cite.format('%s', {
  format: 'text',
  template: '%s',
  lang: '%s'
});
fs.writeFileSync('%s', result, 'utf8');
]], json_file, format_type, style_path, lang, output_file)

  local db = require("refman.db")
  local ok = pcall(function()
    db.exec_cmd(node_cmd(script))
  end)
  os.remove(json_file)

  if not ok then
    os.remove(output_file)
    return nil
  end

  local rf = io.open(output_file, "r")
  if not rf then
    os.remove(output_file)
    return nil
  end
  local result = rf:read("*a")
  rf:close()
  os.remove(output_file)

  if not result or result == "" then
    return nil
  end

  return result:gsub("\n$", "")
end

local function run_csl_async(csl_json_array, style_path, lang, format_type, callback)
  format_type = format_type or "bibliography"
  lang = lang or "de-DE"

  local json_file = os.tmpname()
  local f = io.open(json_file, "w")
  f:write(vim.json.encode(csl_json_array))
  f:close()

  local output_file = os.tmpname()

  local script = string.format([[
const fs = require('fs');
const { Cite } = require('@citation-js/core');
require('@citation-js/plugin-csl');
const raw = fs.readFileSync('%s', 'utf8');
const data = JSON.parse(raw);
const cite = new Cite(data);
const result = cite.format('%s', {
  format: 'text',
  template: '%s',
  lang: '%s'
});
fs.writeFileSync('%s', result, 'utf8');
]], json_file, format_type, style_path, lang, output_file)

  local tmp = os.tmpname()
  local sf = io.open(tmp, "w")
  sf:write(script)
  sf:close()

  local prefix = ""
  local root = get_npm_root()
  if root and root ~= "" then
    prefix = "NODE_PATH=" .. root .. " "
  end
  local cmd = prefix .. "node " .. tmp .. " 2>/dev/null"

  vim.fn.jobstart(cmd, {
    on_exit = function()
      os.remove(tmp)
      os.remove(json_file)
      local rf = io.open(output_file, "r")
      if rf then
        local result = rf:read("*a")
        rf:close()
        os.remove(output_file)
        if result and result ~= "" then
          callback(result:gsub("\n$", ""))
          return
        end
      end
      callback(nil)
    end,
  })
end

-- ── type mapping ─────────────────────────────────────────────────────────────

---Map internal pub_type to CSL type.
---@param pub_type string?
---@return string
local function map_csl_type(pub_type)
  if not pub_type then
    return "article-journal"
  end
  local t = pub_type:lower()
  if t:match("article") or t:match("journal") then return "article-journal" end
  if t:match("review") then return "review" end
  if t:match("book") then return "book" end
  if t:match("chapter") then return "chapter" end
  if t:match("conference") or t:match("paper%-conference") then return "paper-conference" end
  if t == "paper" then return "paper-conference" end
  if t:match("thesis") or t:match("dissertation") then return "thesis" end
  if t:match("report") then return "report" end
  if t:match("dataset") then return "dataset" end
  if t:match("standard") then return "standard" end
  if t:match("edited%-book") then return "book" end
  return "article-journal"
end

---Convert a RefmanEntry to CSL-JSON format.
---@param entry RefmanEntry
---@return table
function M.entry_to_csl_json(entry)
  local csl = {
    type = map_csl_type(entry.pub_type),
    title = entry.title,
    abstract = entry.abstract,
    DOI = entry.doi,
    ISBN = entry.isbn,
    ISSN = entry.issn,
    URL = entry.url,
    publisher = entry.publisher,
    ["container-title"] = entry.journal,
    volume = entry.volume,
    issue = entry.issue,
    page = entry.pages,
  }

  if entry.year and tonumber(entry.year) then
    csl.issued = { ["date-parts"] = { { tonumber(entry.year) } } }
  end

  if entry.author then
    csl.author = {}
    for name in entry.author:gmatch("[^;]+") do
      name = name:match("^%s*(.-)%s*$")
      if name and name ~= "" then
        local last, first = name:match("^%s*(.-),%s*(.-)%s*$")
        if last then
          table.insert(csl.author, { family = last:match("^%s*(.-)%s*$"), given = first:match("^%s*(.-)%s*$") })
        else
          table.insert(csl.author, { literal = name })
        end
      end
    end
  end

  return csl
end

-- ── availability check ───────────────────────────────────────────────────────

---Check if node and citation-js are available.
---@return boolean
function M.is_available()
  local db = require("refman.db")
  local script = [[
try {
  require('@citation-js/core');
  require('@citation-js/plugin-csl');
  console.log('ok');
} catch(e) {
  console.log('missing');
}
]]
  local result = db.exec_cmd(node_cmd(script))
  return result == "ok"
end

-- ── style lookup ─────────────────────────────────────────────────────────────

---Find a CSL style config by key.
---@param style_key string
---@return RefmanCSLStyle|nil
function M.get_style_config(style_key)
  local cfg = require("refman.config.defaults")
  if not cfg.csl or not cfg.csl.styles then
    return nil
  end
  for _, s in ipairs(cfg.csl.styles) do
    if s.key == style_key then
      return s
    end
  end
  return nil
end

-- ── synchronous format (single entry) ───────────────────────────────────────

---Format a RefmanEntry using CSL (synchronous, blocks UI).
---@param entry  RefmanEntry
---@param style_path string Path to a .csl style file
---@param lang string Language code (e.g. "de-DE", "en-US")
---@return string|nil Formatted citation, or nil on failure
function M.format(entry, style_path, lang)
  local csl_json = M.entry_to_csl_json(entry)
  local result = run_csl({ csl_json }, style_path, lang, "bibliography")
  if not result then
    log.warn("CSL formatting failed")
    return nil
  end
  return result
end

-- ── asynchronous format (single entry) ──────────────────────────────────────

---Format a RefmanEntry using CSL asynchronously via jobstart.
---@param entry      RefmanEntry
---@param style_path string Path to a .csl style file
---@param lang       string Language code
---@param callback   fun(citation:string|nil) Called with result on completion
function M.format_async(entry, style_path, lang, callback)
  local csl_json = M.entry_to_csl_json(entry)
  run_csl_async({ csl_json }, style_path, lang, "bibliography", callback)
end

-- ── inline citation ─────────────────────────────────────────────────────────

---Format an inline citation (e.g. "(Doe, 2024)") using CSL.
---@param entry      RefmanEntry
---@param style_path string Path to a .csl style file
---@param lang       string Language code
---@return string|nil
function M.cite_inline(entry, style_path, lang)
  local csl_json = M.entry_to_csl_json(entry)
  local result = run_csl({ csl_json }, style_path, lang, "citation")
  if not result then
    log.warn("CSL inline citation failed")
    return nil
  end
  return result
end

-- ── batch bibliography format ───────────────────────────────────────────────

---Format multiple entries as a bibliography using CSL (sorted, author-dedup).
---@param entries    RefmanEntry[]
---@param style_path string Path to a .csl style file
---@param lang       string Language code
---@return string[]|nil Array of formatted citation lines, or nil on failure
function M.format_batch(entries, style_path, lang)
  local csl_json_array = {}
  for _, entry in ipairs(entries) do
    table.insert(csl_json_array, M.entry_to_csl_json(entry))
  end

  local result = run_csl(csl_json_array, style_path, lang, "bibliography")
  if not result then
    log.warn("CSL batch formatting failed")
    return nil
  end

  local lines = {}
  for line in result:gmatch("[^\n]+") do
    local trimmed = line:gsub("^%s+", ""):gsub("%s+$", "")
    if trimmed ~= "" then
      table.insert(lines, trimmed)
    end
  end

  return lines
end

return M
