---@tag refman.tui
local M = {}

local log = require("refman.log")
local db = require("refman.db")
local citation = require("refman.citation")
local detail = require("refman.ui.detail")
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
  local cfg = config or require("refman.config.defaults")

  local styles = {}
  for _, s in ipairs(cfg.csl.styles or {}) do
    styles[#styles + 1] = {
      key = s.key,
      name = s.name,
    }
  end

  local keys_cfg = cfg.keys.tui

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"

  local win = nil
  local citation_text = nil
  local fetched_entry = nil
  local max_width = math.min(80, vim.o.columns - 8)
  local keys_cfg = cfg.keys.tui

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

  local function already_in_db()
    if not identifier or identifier == "" then
      return false
    end
    local clean_id = identifier:gsub("^https?://doi%.org/", ""):gsub("^doi:", ""):gsub("^DOI:", "")
    local entries = db.get_all_entries()
    for _, e in ipairs(entries) do
      if e.isbn_doi and e.isbn_doi == identifier then
        return true
      end
      if e.isbn_doi and clean_id and e.isbn_doi == clean_id then
        return true
      end
      if e.doi and (e.doi == identifier or e.doi == clean_id) then
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
    if fetched_entry then
      fetched_entry.citation = citation_text
      fetched_entry.isbn_doi = fetched_entry.isbn_doi or identifier
      fetched_entry.tags = db.get_frontmatter_tags()
      db.add_entry(fetched_entry)
      return fetched_entry.title or "Unknown"
    end

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

      if fetched_entry then
        if fetched_entry.abstract then
          local ab = fetched_entry.abstract:sub(1, 200)
          if #fetched_entry.abstract > 200 then ab = ab .. "..." end
          table.insert(lines, "Abstract: " .. ab)
          table.insert(lines, "")
        end
        if fetched_entry.keywords and #fetched_entry.keywords > 0 then
          table.insert(lines, "Keywords: " .. table.concat(fetched_entry.keywords, ", "))
          table.insert(lines, "")
        end
        if fetched_entry.pub_type then
          table.insert(lines, "Type: " .. fetched_entry.pub_type .. (fetched_entry.year and (" | " .. fetched_entry.year) or ""))
          table.insert(lines, "")
        end
      end

      local exists = already_in_db()

      clear_buf_keymaps(buf)
      if exists then
        table.insert(lines, "[Already in bibliography]")
        table.insert(lines, "")
        if keys_cfg.edit then
          table.insert(lines, "[" .. keys_cfg.edit .. "] Edit   [" .. (keys_cfg.quit or "q") .. "] Cancel")
        end

        if keys_cfg.edit then
          vim.keymap.set("n", keys_cfg.edit, function()
            do_insert()
            vim.api.nvim_win_close(win, true)
            local entries = db.get_all_entries()
            local matched = nil
            if fetched_entry then
              for _, e in ipairs(entries) do
                if e.doi and fetched_entry.doi and e.doi == fetched_entry.doi then
                  matched = e
                  break
                end
                if e.title and fetched_entry.title and e.title == fetched_entry.title
                  and e.author and fetched_entry.author and e.author == fetched_entry.author then
                  matched = e
                  break
                end
              end
            end
            if not matched then
              local clean_id = identifier:gsub("^https?://doi%.org/", ""):gsub("^doi:", ""):gsub("^DOI:", "")
              for _, e in ipairs(entries) do
                if e.doi and (e.doi == identifier or e.doi == clean_id) then
                  matched = e
                  break
                end
                if e.isbn_doi and (e.isbn_doi == identifier or e.isbn_doi == clean_id) then
                  matched = e
                  break
                end
              end
            end
            if matched then
              detail.view_entry(matched)
            else
              vim.notify("[refman] Could not find entry in database", vim.log.levels.WARN)
            end
          end, { buffer = buf })
        end
      else
        if keys_cfg.save and keys_cfg.edit then
          table.insert(lines, "[" .. keys_cfg.save .. "] Save   [" .. keys_cfg.edit .. "] Save & Edit   [" .. (keys_cfg.quit or "q") .. "] Cancel")
        end

        if keys_cfg.save then
          vim.keymap.set("n", keys_cfg.save, function()
            do_insert()
            do_save()
            vim.api.nvim_win_close(win, true)
          end, { buffer = buf })
        end
        if keys_cfg.edit then
          vim.keymap.set("n", keys_cfg.edit, function()
            do_insert()
            local title = do_save()
            vim.api.nvim_win_close(win, true)
            local entries = db.get_all_entries()
            local matched = nil
            if fetched_entry then
              for _, e in ipairs(entries) do
                if e.doi and fetched_entry.doi and e.doi == fetched_entry.doi then
                  matched = e
                  break
                end
                if e.title and fetched_entry.title and e.title == fetched_entry.title
                  and e.author and fetched_entry.author and e.author == fetched_entry.author then
                  matched = e
                  break
                end
              end
            end
            if not matched then
              for _, e in ipairs(entries) do
                if e.title and e.title == title then
                  matched = e
                  break
                end
              end
            end
            if matched then
              detail.view_entry(matched)
            else
              vim.notify("[refman] Entry saved, but could not open detail view", vim.log.levels.WARN)
            end
          end, { buffer = buf })
        end
      end
    else
      table.insert(lines, "Could not resolve " .. id_type:upper())
      table.insert(lines, "")
      if keys_cfg.retry then
        table.insert(lines, "[" .. keys_cfg.retry .. "] Retry   [" .. (keys_cfg.quit or "q") .. "] Cancel")
      end

      clear_buf_keymaps(buf)
      if keys_cfg.retry then
        vim.keymap.set("n", keys_cfg.retry, function()
          show_styles()
        end, { buffer = buf })
      end
    end
    if keys_cfg.quit then
      vim.keymap.set("n", keys_cfg.quit, function()
        vim.api.nvim_win_close(win, true)
      end, { buffer = buf })
    end
    set_content(lines)
  end

  show_styles = function()
    local lines = { "Identifier: " .. identifier, "", "Select citation style:" }
    for i, s in ipairs(styles) do
      table.insert(lines, string.format("  %d. %s", i, s.name))
    end

    clear_buf_keymaps(buf)
    for i = 1, #styles do
      local select_key = keys_cfg["select_" .. i]
      if select_key then
        vim.keymap.set("n", select_key, function()
          on_style_selected(i)
        end, { buffer = buf, nowait = true })
      end
    end
    if keys_cfg.select then
      vim.keymap.set("n", keys_cfg.select, function()
        local line = vim.api.nvim_get_current_line()
        local idx = tonumber(line:match("^%s*(%d+)%."))
        if idx and idx <= #styles then
          on_style_selected(idx)
        end
      end, { buffer = buf })
    end
    if keys_cfg.quit then
      vim.keymap.set("n", keys_cfg.quit, function()
        vim.api.nvim_win_close(win, true)
      end, { buffer = buf })
    end

    set_content(lines)
    vim.api.nvim_win_set_cursor(win, { 3, 0 })
  end

  on_style_selected = function(idx)
    local style = styles[idx]
    set_content({ "Identifier: " .. identifier, "", "Fetching citation...", "", "Style: " .. style.name })
    vim.cmd("redraw")

    local fetcher = id_type == "doi" and citation.fetch_doi_citation or citation.fetch_isbn_citation
    local ok, text, entry = pcall(fetcher, identifier, style.key)
    if not ok then
      log.error("fetch crash: " .. tostring(text))
      text = nil
    end

    if not text then
      local alt_type = id_type == "doi" and "isbn" or "doi"
      local alt_fetcher = alt_type == "doi" and citation.fetch_doi_citation or citation.fetch_isbn_citation
      log.info("Retrying as " .. alt_type)
      local ok2, text2, entry2 = pcall(alt_fetcher, identifier, style.key)
      if ok2 and text2 then
        text = text2
        entry = entry2
        vim.notify("[refman] Resolved via " .. alt_type, vim.log.levels.INFO)
      end
    end

    citation_text = text
    fetched_entry = entry
    show_result()
  end

  show_styles()
end

return M
