---@tag refman.tui
local M = {}

local log = require("refman.log")
local db = require("refman.db")
local citation = require("refman.citation")
local config

---@param cfg RefmanConfig
function M.set_config(cfg)
  config = cfg
end

-- ── helpers ──────────────────────────────────────────────────────────────────

local function clear_buf_keymaps(buf)
  local maps = vim.api.nvim_buf_get_keymap(buf, "n")
  for _, m in ipairs(maps) do
    pcall(vim.keymap.del, "n", m.lhs, { buffer = buf })
  end
end

local function wrap_text(text, width)
  local wrapped = {}
  for _, l in ipairs(vim.split(text, "\n")) do
    while #l > width do
      table.insert(wrapped, l:sub(1, width))
      l = l:sub(width + 1)
    end
    table.insert(wrapped, l)
  end
  return wrapped
end

-- ── interactive citation conversion (floating TUI) ───────────────────────────

---@param id_type string "doi"|"isbn"
---@param identifier string
function M.citation_tui(id_type, identifier)
  local cursor_pos = vim.api.nvim_win_get_cursor(0)
  local styles = id_type == "doi" and config.doi_styles or config.isbn_styles

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"

  local win = nil
  local citation_text = nil
  local max_width = math.min(80, vim.o.columns - 8)

  local function set_content(lines)
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false

    local max_line_len = 0
    for _, l in ipairs(lines) do
      if #l > max_line_len then
        max_line_len = #l
      end
    end
    local w = math.max(50, math.min(max_width + 8, max_line_len + 4))
    local h = math.min(vim.o.lines - 2, #lines + 2)
    local col = math.floor((vim.o.columns - w) / 2)
    local row = math.floor((vim.o.lines - h) / 2 - 1)

    if win then
      vim.api.nvim_win_set_config(win, {
        relative = "editor",
        width = w,
        height = h,
        col = col,
        row = row,
      })
      vim.api.nvim_set_current_win(win)
    else
      win = vim.api.nvim_open_win(buf, true, {
        relative = "editor",
        width = w,
        height = h,
        col = col,
        row = row,
        border = "rounded",
        style = "minimal",
      })
    end
  end

  local function already_in_db(cit)
    local author = cit:match("^(.-)%s*:") or "Unknown"
    local title = cit:match(":%s*(.-)%s*[%.;]") or cit:match(":%s*(.+)$") or "Unknown"
    local entries = db.read_markdown_db()
    for _, e in ipairs(entries) do
      if
        (e.author or ""):lower():match("^%s*(.-)%s*$") == author:lower():match("^%s*(.-)%s*$")
        and (e.title or ""):lower():match("^%s*(.-)%s*$") == title:lower():match("^%s*(.-)%s*$")
      then
        return true
      end
    end
    return false
  end

  local function do_insert()
    local mod = vim.bo.modifiable
    vim.bo.modifiable = true
    vim.api.nvim_buf_set_lines(0, cursor_pos[1], cursor_pos[1], false, { citation_text })
    vim.bo.modifiable = mod
  end

  local function do_save()
    local author = citation_text:match("^(.-)%s*:") or "Unknown"
    local title = citation_text:match(":%s*(.-)%s*[%.;]")
      or citation_text:match(":%s*(.+)$")
      or "Unknown"
    db.add_entry({
      author = author,
      title = title,
      citation = citation_text,
      isbn_doi = identifier,
      tags = db.get_frontmatter_tags(),
    })
    return title
  end

  local show_result, show_styles, on_style_selected

  show_result = function()
    local lines = { "Identifier: " .. identifier, "" }

    if citation_text then
      local wrapped = wrap_text(citation_text, max_width)
      for _, l in ipairs(wrapped) do
        table.insert(lines, l)
      end
      table.insert(lines, "")

      local exists = already_in_db(citation_text)

      clear_buf_keymaps(buf)
      if exists then
        table.insert(lines, "[Already in bibliography]")
        table.insert(lines, "")
        table.insert(lines, "[e] Edit   [q] Cancel")

        vim.keymap.set("n", "e", function()
          do_insert()
          vim.api.nvim_win_close(win, true)
          local title = citation_text:match(":%s*(.-)%s*[%.;]")
            or citation_text:match(":%s*(.+)$")
            or "Unknown"
          db.open_database()
          vim.fn.search(vim.fn.escape(title, ".*[]~\\"), "w")
        end, { buffer = buf })
      else
        table.insert(lines, "[s] Save   [e] Save & Edit   [q] Cancel")

        vim.keymap.set("n", "s", function()
          do_insert()
          do_save()
          vim.api.nvim_win_close(win, true)
        end, { buffer = buf })
        vim.keymap.set("n", "e", function()
          do_insert()
          local title = do_save()
          vim.api.nvim_win_close(win, true)
          db.open_database()
          vim.fn.search(vim.fn.escape(title, ".*[]~\\"), "w")
        end, { buffer = buf })
      end
    else
      table.insert(lines, "Could not resolve " .. id_type:upper())
      table.insert(lines, "")
      table.insert(lines, "[r] Retry   [q] Cancel")

      clear_buf_keymaps(buf)
      vim.keymap.set("n", "r", function()
        show_styles()
      end, { buffer = buf })
    end
    vim.keymap.set("n", "q", function()
      vim.api.nvim_win_close(win, true)
    end, { buffer = buf })
    set_content(lines)
  end

  show_styles = function()
    local lines = { "Identifier: " .. identifier, "", "Select citation style:" }
    for i, s in ipairs(styles) do
      table.insert(lines, string.format("  %d. %s", i, s.name))
    end

    clear_buf_keymaps(buf)
    for i = 1, #styles do
      vim.keymap.set("n", tostring(i), function()
        on_style_selected(i)
      end, { buffer = buf, nowait = true })
    end
    vim.keymap.set("n", "<CR>", function()
      local line = vim.api.nvim_get_current_line()
      local idx = tonumber(line:match("^%s*(%d+)%."))
      if idx and idx <= #styles then
        on_style_selected(idx)
      end
    end, { buffer = buf })
    vim.keymap.set("n", "q", function()
      vim.api.nvim_win_close(win, true)
    end, { buffer = buf })

    set_content(lines)
    vim.api.nvim_win_set_cursor(win, { 3, 0 })
  end

  on_style_selected = function(idx)
    set_content({ "Identifier: " .. identifier, "", "Fetching citation...", "", "Style: " .. styles[idx].name })
    vim.cmd("redraw")

    local ok, result = pcall(
      id_type == "doi" and citation.fetch_doi_citation or citation.fetch_isbn_citation,
      identifier,
      styles[idx]
    )
    if not ok then
      log.error("fetch crash: " .. tostring(result))
    end
    citation_text = ok and result or nil
    show_result()
  end

  show_styles()
end

return M
