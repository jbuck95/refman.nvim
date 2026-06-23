---@tag refman
---@mod refman
local M = {}

-- ── config ───────────────────────────────────────────────────────────────────

---@type RefmanConfig
local config = vim.tbl_extend("keep", {}, require("refman.config.defaults"))

---@param opts table?
---@return boolean
local function validate_config(opts)
  local ok, err = pcall(vim.validate, {
    log_level = { opts.log_level, "string", true },
    db_file = { opts.db_file, "string", true },
    db_backend = { opts.db_backend, "string", true },
    source_apis = { opts.source_apis, "table", true },
    csl = { opts.csl, "table", true },
  })
  if not ok then
    vim.notify("[refman] invalid config: " .. tostring(err), vim.log.levels.ERROR)
    return false
  end
  return true
end

---@param opts? RefmanConfig
function M.setup(opts)
  if not opts or vim.tbl_isempty(opts) then
    return
  end
  if not validate_config(opts) then
    return
  end
  config = vim.tbl_extend("force", config, opts)
  local log = require("refman.log")
  log.level = config.log_level
end

-- ── lazy submodule loading ───────────────────────────────────────────────────

local _db, _citation, _tui, _log, _initialized = nil, nil, nil, nil, false

local function init_submodules()
  if _initialized then
    return
  end
  _initialized = true

  _log = require("refman.log")
  _log.level = config.log_level

  _db = require("refman.db")
  _db.set_config(config)

  _citation = require("refman.citation")
  _citation.set_config(config)

  _tui = require("refman.tui")
  _tui.set_config(config)

  local expanded = vim.fn.expand(config.db_file)
  if vim.fn.filereadable(expanded) == 0 and config.db_backend == "markdown" then
    local file = io.open(expanded, "w")
    if file then
      file:write("# Bibliography Database\n\n")
      file:write("<!-- Use :RefImport to add entries, :RefExport to insert citations, :RefOpen to edit -->\n\n")
      file:close()
    end
  elseif config.db_backend == "sqlite" then
    local sqlite = require("refman.db.sqlite")
    sqlite.set_config(config)
    sqlite.init()
  end
end

-- ── public API ───────────────────────────────────────────────────────────────

function M.convert_doi_citation()
  init_submodules()
  local sel = _db.get_visual_selection()
  if sel == "" then
    return
  end
  _tui.citation_tui("doi", sel)
end

function M.convert_isbn_citation()
  init_submodules()
  local sel = _db.get_visual_selection()
  if sel == "" then
    return
  end
  _tui.citation_tui("isbn", sel)
end

function M.convert_citation()
  init_submodules()
  local sel = _db.get_visual_selection()
  if sel == "" then
    return
  end
  local id_type = sel:match("^%d[%dX]*$") and "isbn" or "doi"
  _tui.citation_tui(id_type, sel)
end

---Insert an inline citation for a DOI/ISBN via CSL.
---@param style_key string? CSL style key
function M.cite_inline_citation(style_key)
  init_submodules()
  local sel = _db.get_visual_selection()
  if sel == "" then
    return
  end

  local cfg = config or require("refman.config.defaults")
  style_key = style_key or cfg.csl.default_style

  local style = nil
  if cfg.csl.styles then
    for _, s in ipairs(cfg.csl.styles) do
      if s.key == style_key then
        style = s
        break
      end
    end
  end
  if not style then
    vim.notify("[refman] Unknown CSL style: " .. style_key, vim.log.levels.ERROR)
    return
  end

  local csl = require("refman.csl")
  if not csl.is_available() then
    vim.notify("[refman] citation-js not available. Run: npm install -g @citation-js/core @citation-js/plugin-csl", vim.log.levels.ERROR)
    return
  end

  local id_type = sel:match("^%d[%dX]*$") and "isbn" or "doi"
  local fetcher = id_type == "doi" and _citation.fetch_doi_citation or _citation.fetch_isbn_citation
  local _, entry = fetcher(sel, style_key)

  if not entry then
    vim.notify("[refman] Could not fetch metadata for: " .. sel, vim.log.levels.WARN)
    return
  end

  local inline = csl.cite_inline(entry, style.path, style.lang)
  if not inline then
    local fallback = (entry.author or "Unknown") .. " (" .. (entry.year or "n.d.") .. ")"
    vim.notify("[refman] CSL inline failed, using fallback: " .. fallback, vim.log.levels.WARN)
    inline = fallback
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local mod = vim.bo.modifiable
  vim.bo.modifiable = true
  vim.api.nvim_buf_set_lines(0, cursor[1], cursor[1], false, { inline })
  vim.bo.modifiable = mod
  vim.notify("Inline citation inserted: " .. inline, vim.log.levels.INFO)
end

function M.import_current_line()
  init_submodules()
  local line = vim.api.nvim_get_current_line()
  if line == "" then
    vim.notify("No line to import", vim.log.levels.WARN)
    return
  end

  local entry = {}

  local author_match = line:match("^([^,]+,%s*[^:%.]+)")
  if author_match then
    entry.author = author_match:match("^%s*(.-)%s*$")
  else
    entry.author = "Unknown Author"
  end

  local title_match = line:match("%*([^%*]+)%*")
    or line:match("\"([^\"]+)\"")
    or line:match("^[^:]+:%s*(.-)%.")
    or line:match("^[^%.]+%.%s*(.-)%.")
  entry.title = title_match or "Unknown Title"
  entry.citation = line:match("^%s*(.-)%s*$")
  entry.source = "manual"

  if _db.add_entry(entry) then
    vim.notify("Entry imported: " .. entry.title, vim.log.levels.INFO)
  else
    vim.notify("Failed to add entry", vim.log.levels.ERROR)
  end
end

function M.open_database()
  init_submodules()
  _db.open_database()
end

function M.export_citation()
  init_submodules()
  require("refman.telescope.browser").open()
end

function M.export_citations_multi()
  init_submodules()
  require("refman.telescope.browser").open()
end

function M.open_log()
  local log = require("refman.log")
  log.open_log()
end

function M.clear_cache()
  init_submodules()
  _citation.clear_cache()
  vim.notify("Citation cache cleared", vim.log.levels.INFO)
end

function M.migrate_to_sqlite()
  init_submodules()
  local sqlite = require("refman.db.sqlite")
  if not sqlite.is_available() then
    vim.notify("[refman] sqlite3 CLI not found -- cannot migrate", vim.log.levels.ERROR)
    return
  end

  local markdown = require("refman.db.markdown")
  markdown.set_config(config)
  local entries = markdown.read_all()

  if #entries == 0 then
    vim.notify("[refman] No entries in markdown database to migrate", vim.log.levels.WARN)
    return
  end

  sqlite.set_config(config)
  sqlite.init()
  local count = sqlite.import_entries(entries)

  config.db_backend = "sqlite"
  vim.notify(string.format("[refman] Migrated %d entries to SQLite at %s", count, config.db_file:gsub("%.md$", ".sqlite3")), vim.log.levels.INFO)
end

function M.search_entries()
  init_submodules()
  local query = vim.fn.input("Refman search: ")
  if query == "" then
    return
  end
  require("refman.telescope.browser").open({ query = query })
end

-- ── user commands ────────────────────────────────────────────────────────────

local function def_cmd(name, fn, opts)
  opts = opts or {}
  opts.force = true
  vim.api.nvim_create_user_command(name, fn, opts)
end

def_cmd("DOI", function()
  M.convert_doi_citation()
end, { range = true })

def_cmd("ISBN", function()
  M.convert_isbn_citation()
end, { range = true })

def_cmd("RefCite", function()
  M.cite_inline_citation()
end, { range = true })

def_cmd("RefImport", function()
  M.import_current_line()
end)

def_cmd("RefBrowse", function(opts)
  init_submodules()
  require("refman.telescope.browser").open({ query = opts.args ~= "" and opts.args or nil })
end, { nargs = "?" })

def_cmd("RefSearch", function(opts)
  init_submodules()
  if opts.args and opts.args ~= "" then
    require("refman.telescope.browser").open({ query = opts.args })
  else
    local query = vim.fn.input("Refman search: ")
    if query ~= "" then
      require("refman.telescope.browser").open({ query = query })
    end
  end
end, { nargs = "?" })

def_cmd("RefOpen", function()
  M.open_database()
end)

def_cmd("RefExport", function()
  M.export_citation()
end)

def_cmd("RefMulti", function()
  M.export_citations_multi()
end)

def_cmd("RefLog", function()
  M.open_log()
end)

def_cmd("RefCacheClear", function()
  M.clear_cache()
end)

def_cmd("RefMigrate", function()
  M.migrate_to_sqlite()
end)

-- ── <Plug> mappings ──────────────────────────────────────────────────────────

vim.keymap.set("n", "<Plug>(RefmanDOI)", function()
  M.convert_doi_citation()
end, { silent = true })

vim.keymap.set("n", "<Plug>(RefmanISBN)", function()
  M.convert_isbn_citation()
end, { silent = true })

vim.keymap.set("n", "<Plug>(RefmanCite)", function()
  M.cite_inline_citation()
end, { silent = true })

vim.keymap.set("n", "<Plug>(RefmanImport)", function()
  M.import_current_line()
end, { silent = true })

vim.keymap.set("n", "<Plug>(RefmanOpen)", function()
  M.open_database()
end, { silent = true })

vim.keymap.set("n", "<Plug>(RefmanBrowse)", function()
  M.export_citation()
end, { silent = true })

vim.keymap.set("n", "<Plug>(RefmanExport)", function()
  M.export_citation()
end, { silent = true })

vim.keymap.set("n", "<Plug>(RefmanMulti)", function()
  M.export_citations_multi()
end, { silent = true })

vim.keymap.set("n", "<Plug>(RefmanMigrate)", function()
  M.migrate_to_sqlite()
end, { silent = true })

vim.keymap.set("n", "<Plug>(RefmanSearch)", function()
  M.search_entries()
end, { silent = true })

return M
