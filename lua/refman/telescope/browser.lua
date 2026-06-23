---@tag refman.telescope.browser
---Telescope-based browser for bibliography entries with CSL formatting.
local M = {}

local has_telescope, telescope = pcall(require, "telescope")
if not has_telescope then
  telescope = nil
end

local function db()
  return require("refman.db")
end

local function backend()
  return db().get_backend()
end

local function wrap_text(text, width)
  local wrapped = {}
  for _, l in ipairs(vim.split(text or "", "\n")) do
    while #l > width do
      table.insert(wrapped, l:sub(1, width))
      l = l:sub(width + 1)
    end
    table.insert(wrapped, l)
  end
  return wrapped
end

local function format_bibliography_csl(picked)
  local cfg = require("refman").config
  if not cfg.csl or not cfg.csl.enabled then
    return nil
  end

  local csl = require("refman.csl")
  if not csl.is_available() then
    return nil
  end

  local default_style = cfg.csl.default_style or "din-1505-2"
  local style = nil
  if cfg.csl.styles then
    for _, s in ipairs(cfg.csl.styles) do
      if s.key == default_style then
        style = s
        break
      end
    end
  end
  if not style then
    return nil
  end

  return csl.format_batch(picked, style.path, style.lang)
end

---Open the Telescope bibliography browser.
---@param opts? {query?:string, multi?:boolean}
function M.open(opts)
  if not telescope then
    vim.notify("[refman] telescope.nvim is required for browsing", vim.log.levels.ERROR)
    return
  end

  opts = opts or {}

  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")

  local entries
  if opts.query and opts.query ~= "" then
    entries = db().search_entries(opts.query)
  else
    entries = db().get_all_entries()
  end

  if #entries == 0 then
    vim.notify("[refman] No entries found", vim.log.levels.WARN)
    return
  end

  local detail_ui = require("refman.ui.detail")
  local keys_cfg = require("refman").config.keys.telescope

  local prompt_title = "Bibliography"
  if keys_cfg.detail then
    prompt_title = prompt_title .. " | " .. keys_cfg.detail .. " Detail"
  end
  if keys_cfg.toggle_multi then
    prompt_title = prompt_title .. " | " .. keys_cfg.toggle_multi .. " Multi"
  end
  if keys_cfg.bibliography then
    prompt_title = prompt_title .. " | " .. keys_cfg.bibliography .. " Biblio"
  end

  pickers.new({}, {
    prompt_title = prompt_title,
    results_title = "Entries",
    preview_title = "Entry Details",
    layout_strategy = "horizontal",
    layout_config = {
      horizontal = {
        mirror = false,
        preview_width = 0.55,
        width = 0.90,
        height = 0.90,
      },
    },
    finder = finders.new_table({
      results = entries,
      entry_maker = function(entry)
        local display = (entry.author or "Unknown") .. "  --  " .. (entry.title or "Untitled")
        local ordinal = table.concat({
          entry.author or "",
          entry.title or "",
          entry.citation or "",
          entry.abstract or "",
          entry.journal or "",
          entry.tags or "",
          entry.notes or "",
          entry.year or "",
          entry.doi or "",
        }, " ")
        return {
          value = entry,
          display = display,
          ordinal = ordinal,
        }
      end,
    }),
    sorting_strategy = "ascending",
    sorter = conf.generic_sorter({}),
    previewer = require("telescope.previewers").new_buffer_previewer({
      title = "Entry Details",
      define_preview = function(self, entry)
        local e = entry.value
        local lines = {}
        local w = vim.api.nvim_win_get_width(self.state.winid) - 4
        w = math.max(w, 40)

        local function add(s)
          table.insert(lines, s)
        end
        local function sep()
          add(string.rep("\226\148\128", w))
        end
        local function section(title)
          local pad = math.max(0, math.floor((w - #title - 4) / 2))
          add(string.rep(" ", pad) .. "[ " .. title .. " ]")
        end
        local function field(name, value)
          if not value or value == "" then return end
          local clean = value:gsub("\n", " ")
          add(string.format("  %-12s %s", name .. ":", clean))
        end

        -- Metadata section
        sep()
        field("Author", e.author)
        field("Title", e.title)
        field("Year", e.year)
        field("Type", e.pub_type)
        if e.journal then
          local j = e.journal
          if e.volume then j = j .. " " .. e.volume end
          if e.issue then j = j .. "(" .. e.issue .. ")" end
          if e.pages then j = j .. ", pp. " .. e.pages end
          field("Journal", j)
        end
        field("Publisher", e.publisher)
        if e.doi then field("DOI", e.doi) end
        if e.isbn then field("ISBN", e.isbn) end
        if e.issn then field("ISSN", e.issn) end
        if e.url then field("URL", e.url) end
        if e.pmid then field("PMID", e.pmid) end
        if e.keywords then
          local kw = e.keywords
          if type(kw) == "table" then kw = table.concat(kw, ", ") end
          if kw ~= "" then field("Keywords", kw) end
        end
        if e.source then field("Source", e.source) end

        if e.citation and e.citation ~= "" then
          add("")
          sep()
          add("  Citation:")
          add("")
          for _, l in ipairs(wrap_text(e.citation, w - 2)) do
            add("  " .. l)
          end
        end

        if (e.abstract and e.abstract ~= "") or (e.notes and e.notes ~= "") or (e.tags and e.tags ~= "") then
          add("")
          sep()
          section("Notes & Tags")
          add("")

          if e.abstract and e.abstract ~= "" then
            add("  Abstract:")
            for _, l in ipairs(wrap_text(e.abstract, w - 4)) do
              add("    " .. l)
            end
            add("")
          end

          if e.notes and e.notes ~= "" then
            add("  Notes:")
            for _, l in ipairs(wrap_text(e.notes, w - 4)) do
              add("    " .. l)
            end
            add("")
          end

          if e.tags and e.tags ~= "" then
            add("  Tags: " .. e.tags:gsub("\n", " "))
          end
        end

        vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
        vim.api.nvim_buf_set_option(self.state.bufnr, "filetype", "markdown")
      end,
    }),
    attach_mappings = function(prompt_bufnr)
      actions.select_default:replace(function()
        local picker = action_state.get_current_picker(prompt_bufnr)
        local selected = picker:get_multi_selection()
        if not selected or #selected == 0 then
          local sel = action_state.get_selected_entry()
          if not sel then
            return
          end
          selected = { sel }
        end
        actions.close(prompt_bufnr)

        if #selected == 1 then
          local cit = selected[1].value.citation
          if cit and cit ~= "" then
            local row, col = unpack(vim.api.nvim_win_get_cursor(0))
            vim.api.nvim_buf_set_text(0, row - 1, col, row - 1, col, { cit })
            vim.notify("Citation inserted: " .. (selected[1].value.title or "entry"), vim.log.levels.INFO)
          end
        else
          local row = vim.api.nvim_win_get_cursor(0)[1]
          local citations = {}
          for _, s in ipairs(selected) do
            local cit = s.value.citation
            if cit and cit ~= "" then
              table.insert(citations, cit)
            end
          end
          for i, cit in ipairs(citations) do
            vim.api.nvim_buf_set_lines(0, row, row, false, { cit })
            row = row + 1
            if i < #citations then
              vim.api.nvim_buf_set_lines(0, row, row, false, { "" })
              row = row + 1
            end
          end
          if #citations > 0 then
            vim.notify("Inserted " .. #citations .. " citation(s)", vim.log.levels.INFO)
          end
        end
      end)

      local function on_selection(fn)
        return function()
          local selection = action_state.get_selected_entry()
          if selection then
            fn(selection)
          end
        end
      end

      if keys_cfg.detail then
        vim.keymap.set({ "i", "n" }, keys_cfg.detail, on_selection(function(sel)
          actions.close(prompt_bufnr)
          detail_ui.view_entry(sel.value)
        end), { buffer = prompt_bufnr })
      end

      if keys_cfg.delete then
        vim.keymap.set({ "i", "n" }, keys_cfg.delete, on_selection(function(sel)
          local e = sel.value
          local confirm = vim.fn.confirm("Delete '" .. (e.title or "this entry") .. "'?", "&Yes\n&No", 2)
          if confirm == 1 then
            if e.id then
              backend().delete_entry(e.id)
            end
            vim.notify("Entry deleted: " .. e.title, vim.log.levels.INFO)
            actions.close(prompt_bufnr)
            M.open(opts)
          end
        end), { buffer = prompt_bufnr })
      end

      if keys_cfg.toggle_multi then
        vim.keymap.set("i", keys_cfg.toggle_multi, function() actions.toggle_selection(prompt_bufnr) end, { buffer = prompt_bufnr })
        vim.keymap.set("n", keys_cfg.toggle_multi, function() actions.toggle_selection(prompt_bufnr) end, { buffer = prompt_bufnr })
      end

      if keys_cfg.bibliography then
        vim.keymap.set({ "i", "n" }, keys_cfg.bibliography, function()
          local picker = action_state.get_current_picker(prompt_bufnr)
          local selected = picker:get_multi_selection()
          if not selected or #selected == 0 then
            local sel = action_state.get_selected_entry()
            selected = sel and { sel } or {}
          end
          if #selected == 0 then
            return
          end
          local picked = {}
          for _, s in ipairs(selected) do
            table.insert(picked, s.value)
          end

          local bib_lines = format_bibliography_csl(picked)
          if not bib_lines or #bib_lines == 0 then
            vim.notify("[refman] CSL formatting failed. Is citation-js installed?", vim.log.levels.WARN)
            return
          end

          actions.close(prompt_bufnr)
          local row = vim.api.nvim_win_get_cursor(0)[1]
          for i, l in ipairs(bib_lines) do
            vim.api.nvim_buf_set_lines(0, row, row, false, { l })
            row = row + 1
            if i < #bib_lines then
              vim.api.nvim_buf_set_lines(0, row, row, false, { "" })
              row = row + 1
            end
          end
          vim.notify("Inserted bibliography with " .. #picked .. " entries", vim.log.levels.INFO)
        end, { buffer = prompt_bufnr })
      end

      return true
    end,
  }):find()
end

return M
