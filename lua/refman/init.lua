---@tag refman
---@mod refman
local M = {}

-- ── config ───────────────────────────────────────────────────────────────────

---@type RefmanConfig
local config = vim.tbl_extend("keep", {}, require("refman.config.defaults"))

-- Validate config schema
---@param opts table?
---@return boolean
local function validate_config(opts)
  local ok, err = pcall(vim.validate, {
    log_level = { opts.log_level, "string", true },
    db_file = { opts.db_file, "string", true },
    doi_styles = { opts.doi_styles, "table", true },
    isbn_styles = { opts.isbn_styles, "table", true },
  })
  if not ok then
    vim.notify("[refman] invalid config: " .. tostring(err), vim.log.levels.ERROR)
    return false
  end
  return true
end

---Override default configuration. Calling setup() is optional — the plugin
---works out-of-the-box with built-in defaults.
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

  _tui = require("refman.tui")
  _tui.set_config(config)

  -- Auto-create bibliography database file
  local expanded = vim.fn.expand(config.db_file)
  if vim.fn.filereadable(expanded) == 0 then
    local file = io.open(expanded, "w")
    if file then
      file:write("# Bibliography Database\n\n")
      file:write("<!-- Use :RefImport to add entries, :RefExport to insert citations, :RefOpen to edit -->\n\n")
      file:close()
    end
  end
end

-- ── public API ───────────────────────────────────────────────────────────────

---Convert a visually selected DOI into a citation via interactive TUI.
function M.convert_doi_citation()
  init_submodules()
  local sel = _db.get_visual_selection()
  if sel == "" then
    return
  end
  _tui.citation_tui("doi", sel)
end

---Convert a visually selected ISBN into a citation via interactive TUI.
function M.convert_isbn_citation()
  init_submodules()
  local sel = _db.get_visual_selection()
  if sel == "" then
    return
  end
  _tui.citation_tui("isbn", sel)
end

---Import the current buffer line as a bibliography entry.
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

  if _db.add_entry(entry) then
    vim.notify("Entry imported: " .. entry.title, vim.log.levels.INFO)
  else
    vim.notify("Failed to add entry", vim.log.levels.ERROR)
  end
end

---Open the bibliography database file.
function M.open_database()
  init_submodules()
  _db.open_database()
end

---Select and insert a single citation via fzf.
function M.export_citation()
  init_submodules()
  local entries = _db.read_markdown_db()
  if #entries == 0 then
    vim.notify("No entries in bibliography database", vim.log.levels.WARN)
    return
  end

  local preview_script = "/tmp/bib_preview.sh"
  local f = io.open(preview_script, "w")
  f:write([=[#!/usr/bin/env bash
IFS=$'\x1f' read -r -a fields <<< "$*"
printf "\033[1mCitation:\033[0m\n%s\n\n\033[1mISBN/DOI:\033[0m\n%s\n\n\033[1mTags:\033[0m\n%s\n" "${fields[2]}" "${fields[3]}" "${fields[4]}"
]=])
  f:close()
  os.execute("chmod +x " .. preview_script)

  local fzf_entries = _db.build_fzf_entries(entries)

  vim.fn["fzf#run"]({
    source = fzf_entries,
    sink = function(line)
      local entry_num = tonumber(line:match("^(%d+)\x1f"))
      if entry_num and entries[entry_num] then
        local cit = entries[entry_num].citation
        local row, col = unpack(vim.api.nvim_win_get_cursor(0))
        vim.api.nvim_buf_set_text(0, row - 1, col, row - 1, col, { cit })
        vim.notify("Citation inserted: " .. entries[entry_num].title, vim.log.levels.INFO)
      end
    end,
    options = {
      "--prompt",
      "Select Citation> ",
      "--delimiter",
      "\x1f",
      "--with-nth",
      "2",
      "--preview-window",
      "down:40%",
      "--preview",
      '/tmp/bib_preview.sh {} | fold -s -w $FZF_PREVIEW_COLUMNS',
      "--height",
      "70%",
      "--layout",
      "reverse",
      "--border",
    },
  })
end

---Select and insert multiple citations via fzf.
function M.export_citations_multi()
  init_submodules()
  local entries = _db.read_markdown_db()
  if #entries == 0 then
    vim.notify("No entries in bibliography database", vim.log.levels.WARN)
    return
  end

  local fzf_entries = _db.build_fzf_entries(entries)
  local original_pos = vim.api.nvim_win_get_cursor(0)

  vim.fn["fzf#run"]({
    source = fzf_entries,
    ["sink*"] = function(selected)
      if not selected or #selected == 0 then
        return
      end
      local picked = {}
      for _, line in ipairs(selected) do
        local entry_num = tonumber(line:match("^(%d+)\x1f"))
        if entry_num and entries[entry_num] then
          table.insert(picked, entries[entry_num])
        end
      end
      local bib_lines = _db.format_bibliography(picked)
      local row = original_pos[1]
      for i, l in ipairs(bib_lines) do
        vim.api.nvim_buf_set_lines(0, row, row, false, { l })
        row = row + 1
        if i < #bib_lines then
          vim.api.nvim_buf_set_lines(0, row, row, false, { "" })
          row = row + 1
        end
      end
      vim.notify("Inserted " .. #picked .. " citations", vim.log.levels.INFO)
    end,
    options = {
      "--prompt",
      "Select Citations (Tab=multi)> ",
      "--multi",
      "--delimiter",
      "\x1f",
      "--with-nth",
      "2",
      "--height",
      "70%",
      "--layout",
      "reverse",
      "--border",
    },
  })
end

function M.open_log()
  local log = require("refman.log")
  log.open_log()
end

-- ── user commands ────────────────────────────────────────────────────────────

vim.api.nvim_create_user_command("DOI", function()
  M.convert_doi_citation()
end, { range = true })

vim.api.nvim_create_user_command("ISBN", function()
  M.convert_isbn_citation()
end, { range = true })

vim.api.nvim_create_user_command("RefImport", function()
  M.import_current_line()
end, {})

vim.api.nvim_create_user_command("RefOpen", function()
  M.open_database()
end, {})

vim.api.nvim_create_user_command("RefExport", function()
  M.export_citation()
end, {})

vim.api.nvim_create_user_command("RefMulti", function()
  M.export_citations_multi()
end, {})

vim.api.nvim_create_user_command("RefLog", function()
  M.open_log()
end, {})

-- ── <Plug> mappings ──────────────────────────────────────────────────────────

vim.keymap.set("n", "<Plug>(RefmanDOI)", function()
  M.convert_doi_citation()
end, { silent = true })

vim.keymap.set("n", "<Plug>(RefmanISBN)", function()
  M.convert_isbn_citation()
end, { silent = true })

vim.keymap.set("n", "<Plug>(RefmanImport)", function()
  M.import_current_line()
end, { silent = true })

vim.keymap.set("n", "<Plug>(RefmanOpen)", function()
  M.open_database()
end, { silent = true })

vim.keymap.set("n", "<Plug>(RefmanExport)", function()
  M.export_citation()
end, { silent = true })

vim.keymap.set("n", "<Plug>(RefmanMulti)", function()
  M.export_citations_multi()
end, { silent = true })

return M
