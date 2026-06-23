---@tag refman.citation
local M = {}

local log = require("refman.log")
local db = require("refman.db")
local config

-- ── citation cache ────────────────────────────────────────────────────────────

local cache_file = vim.fn.stdpath("cache") .. "/refman-cache.json"

local function load_cache()
  local f = io.open(cache_file, "r")
  if not f then
    return {}
  end
  local content = f:read("*all")
  f:close()
  if not content or content == "" then
    return {}
  end
  local ok, data = pcall(vim.json.decode, content)
  return (ok and data) and data or {}
end

local function save_cache(cache)
  local f = io.open(cache_file, "w")
  if f then
    f:write(vim.json.encode(cache))
    f:close()
  end
end

local function cache_key(identifier, style_key)
  return identifier .. "::" .. style_key
end

-- ── config helpers ────────────────────────────────────────────────────────────

function M.set_config(cfg)
  config = cfg
end

local function get_config()
  return config or require("refman.config.defaults")
end

local function source_enabled(name)
  local apis = get_config().source_apis
  return apis and apis[name] and apis[name].enabled
end

-- ── CSL helpers ──────────────────────────────────────────────────────────────

local function get_csl_style_config(style_key)
  local cfg = get_config()
  if not style_key then
    style_key = cfg.csl.default_style or "din-1505-2"
  end
  if cfg.csl.styles then
    for _, s in ipairs(cfg.csl.styles) do
      if s.key == style_key then
        return s
      end
    end
  end
  return nil
end

-- ── rich metadata fetch via source modules ────────────────────────────────────

---Fetch a RefmanEntry from configured source modules.
---@param doi string Clean DOI
---@return RefmanEntry?
function M.fetch_doi_entry(doi)
  local sources = {
    { name = "crossref", priority = 1 },
    { name = "openalex", priority = 2 },
  }

  for _, src in ipairs(sources) do
    if source_enabled(src.name) then
      local ok, mod = pcall(require, "refman.source." .. src.name)
      if ok and mod then
        log.debug("Source " .. src.name .. ": fetching DOI " .. doi)
        local entry = mod.fetch(doi)
        if entry then
          return entry
        end
      end
    end
  end

  return nil
end

-- ── CSL-only formatting ──────────────────────────────────────────────────────

---Format a RefmanEntry using CSL.
---@param entry     RefmanEntry
---@param style_key string Key of CSL style in config.csl.styles
---@return string|nil
function M.format_entry(entry, style_key)
  local cfg = get_config()
  local style = get_csl_style_config(style_key)
  if not style then
    log.warn("Unknown CSL style: " .. (style_key or "nil"))
    return nil
  end

  local csl = require("refman.csl")
  if not csl.is_available() then
    log.error("citation-js not available — install: npm install -g @citation-js/core @citation-js/plugin-csl")
    return nil
  end

  local result = csl.format(entry, style.path, style.lang)
  if not result or result == "" then
    log.error("CSL formatting failed for style " .. style_key)
    return nil
  end

  return result
end

-- ── DOI citation fetching ────────────────────────────────────────────────────

local function clean_doi(raw)
  return (raw:gsub("^https?://doi%.org/", "")
    :gsub("^doi:", "")
    :gsub("^DOI:", "")
    :gsub("[.,;:)%]%[\"?!']+$", "")
    :gsub("^%s+", "")
    :gsub("%s+$", ""))
end

---@param doi string
---@param style_key string Key of CSL style
---@return string|nil citation_text
---@return RefmanEntry|nil entry
function M.fetch_doi_citation(doi, style_key)
  doi = clean_doi(doi)
  local ckey = cache_key(doi, style_key or get_config().csl.default_style)
  local cache = load_cache()
  if cache[ckey] then
    log.debug("DOI cache hit: " .. ckey)
    return cache[ckey]
  end

  local entry = M.fetch_doi_entry(doi)
  if not entry then
    log.warn("DOI " .. doi .. ": no metadata found from any source")
    return nil
  end

  local citation = M.format_entry(entry, style_key)
  if not citation then
    log.error("DOI " .. doi .. ": CSL formatting failed")
    return nil
  end

  entry.citation = citation
  cache[ckey] = citation
  save_cache(cache)
  return citation, entry
end

-- ── ISBN citation fetching ───────────────────────────────────────────────────

local function parse_openlibrary(data, isbn)
  local key = "ISBN:" .. isbn
  local item = data[key]
  if not item then
    return nil
  end

  local entry = { isbn = isbn, source = "isbn", isbn_doi = isbn, pub_type = "book" }

  entry.title = item.title
  if item.subtitle then
    entry.title = entry.title .. ": " .. item.subtitle
  end

  local authors_list = {}
  if item.authors then
    for _, a in ipairs(item.authors) do
      table.insert(authors_list, a.name)
    end
  end

  if item.by_statement then
    local bs = item.by_statement:gsub("%.$", "")
    if bs:lower():match("^edited by") or bs:lower():match("^edited ") then
      entry.pub_type = "edited-book"
    end
  end

  if #authors_list == 0 and item.by_statement then
    local bs = item.by_statement:gsub("%.$", "")
    local stripped = bs:gsub("^[Ee]dited by ", "")
    if stripped == bs then
      stripped = bs:gsub("^[Ee]dited ", "")
    end
    bs = stripped

    for _, sep in ipairs({"/", "; ", ";", ", "}) do
      local parts = vim.split(bs, sep, { plain = true, trimempty = true })
      if #parts > 1 then
        for _, part in ipairs(parts) do
          part = part:match("^%s*(.-)%s*$")
          if part ~= "" then
            table.insert(authors_list, part)
          end
        end
        break
      end
    end

    if #authors_list == 0 then
      local name = bs:match("^%s*(.-)%s*$")
      if name and name ~= "" then
        authors_list = { name }
      end
    end
  end
  entry.author = #authors_list > 0 and table.concat(authors_list, "; ") or nil

  entry.publisher = (item.publishers and item.publishers[1] and item.publishers[1].name) or nil

  if item.publish_date then
    entry.year = item.publish_date:match("(%d%d%d%d)")
  end

  return entry
end

---@param isbn string
---@param style_key string Key of CSL style
---@return string|nil citation_text
---@return RefmanEntry|nil entry
function M.fetch_isbn_citation(isbn, style_key)
  isbn = isbn:gsub("[^0-9X]", "")
  local ckey = cache_key(isbn, style_key or get_config().csl.default_style)
  local cache = load_cache()
  if cache[ckey] then
    log.debug("ISBN cache hit: " .. ckey)
    return cache[ckey]
  end

  log.debug("ISBN lookup for " .. isbn)
  local ol_raw = db.exec_cmd(
    'curl -s -L --connect-timeout 10 "https://openlibrary.org/api/books?bibkeys=ISBN:'
      .. isbn
      .. '&format=json&jscmd=data"'
  )

  local entry = nil
  if ol_raw and ol_raw ~= "" then
    local ok, data = pcall(vim.json.decode, ol_raw)
    if ok and data then
      entry = parse_openlibrary(data, isbn)
    end
  end

  if not entry then
    log.warn("ISBN " .. isbn .. ": OpenLibrary returned no data")
    return nil
  end

  local citation = M.format_entry(entry, style_key)
  if not citation then
    log.error("ISBN " .. isbn .. ": CSL formatting failed")
    return nil
  end

  entry.citation = citation
  cache[ckey] = citation
  save_cache(cache)
  return citation, entry
end

---Clear the citation cache file.
function M.clear_cache()
  os.remove(cache_file)
  log.info("Citation cache cleared")
end

return M
