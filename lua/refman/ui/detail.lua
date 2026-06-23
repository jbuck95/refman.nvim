---@tag refman.ui.detail
---Entry detail view and edit buffer.
local M = {}

local function backend()
  return require("refman.db").get_backend()
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

local function separator(width)
  return string.rep("\226\148\128", width)
end

local function field(name, value, width)
  if not value or value == "" then
    return nil
  end
  local clean = value:gsub("\n", " ")
  local label = string.format("  %-12s ", name .. ":")
  local indent = string.rep(" ", #label)
  local available = width - #label
  local wrapped = {}
  while #clean > 0 do
    if #clean <= available then
      wrapped[#wrapped + 1] = clean
      break
    end
    local chunk = clean:sub(1, available)
    local pos = chunk:match(".*() ")
    local cut = pos or available
    wrapped[#wrapped + 1] = clean:sub(1, cut - 1)
    clean = clean:sub(cut + 1)
  end
  local lines = {}
  for i, w in ipairs(wrapped) do
    lines[i] = (i == 1 and label or indent) .. w
  end
  return lines
end

---Open a read-only buffer showing all entry fields.
---@param entry RefmanEntry
---@param orig_buf integer? Buffer to copy citation to on 'c'
function M.view_entry(entry, orig_buf)
  if not entry then
    vim.notify("[refman] Invalid entry", vim.log.levels.ERROR)
    return
  end

  orig_buf = orig_buf or vim.api.nvim_get_current_buf()

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"

  local width = math.min(80, vim.o.columns - 4)
  local lines = {}

  local function append(t)
    if t then
      vim.list_extend(lines, t)
    end
  end

  table.insert(lines, separator(width))
  append(field("Author", entry.author, width) or { "  Author:       (unknown)" })
  append(field("Title", entry.title, width) or { "  Title:        (unknown)" })

  if entry.year then
    append(field("Year", entry.year, width))
  end
  if entry.pub_type then
    append(field("Type", entry.pub_type, width))
  end
  if entry.journal then
    local j = entry.journal
    if entry.volume then j = j .. " " .. entry.volume end
    if entry.issue then j = j .. "(" .. entry.issue .. ")" end
    if entry.pages then j = j .. ", pp. " .. entry.pages end
    append(field("Journal", j, width))
  end
  if entry.publisher then
    append(field("Publisher", entry.publisher, width))
  end
  if entry.doi then
    append(field("DOI", entry.doi, width))
  end
  if entry.isbn then
    append(field("ISBN", entry.isbn, width))
  end
  if entry.pmid then
    append(field("PMID", entry.pmid, width))
  end
  if entry.url then
    append(field("URL", entry.url, width))
  end

  if entry.keywords and type(entry.keywords) == "table" and #entry.keywords > 0 then
    append(field("Keywords", table.concat(entry.keywords, ", "), width))
  elseif entry.keywords and type(entry.keywords) == "string" and entry.keywords ~= "" then
    append(field("Keywords", entry.keywords, width))
  end

  local src = entry.source or "manual"
  local added = entry.added_at or ""
  local updated = entry.updated_at or ""
  local meta = string.format("Source: %s  |  Added: %s", src, added)
  if updated and updated ~= "" then
    meta = meta .. "  |  Updated: " .. updated
  end
  append(field("Meta", meta, width))

  if entry.citation then
    table.insert(lines, "")
    table.insert(lines, separator(width))
    table.insert(lines, "Citation:")
    vim.list_extend(lines, wrap_text(entry.citation, width))
  end

  if entry.abstract and entry.abstract ~= "" then
    table.insert(lines, "")
    table.insert(lines, separator(width))
    table.insert(lines, "Abstract:")
    vim.list_extend(lines, wrap_text(entry.abstract, width))
  end

  if entry.notes and entry.notes ~= "" then
    table.insert(lines, "")
    table.insert(lines, separator(width))
    table.insert(lines, "Notes:")
    vim.list_extend(lines, wrap_text(entry.notes, width))
  end

  if entry.tags and entry.tags ~= "" then
    table.insert(lines, "")
    table.insert(lines, separator(width))
    table.insert(lines, "Tags: " .. entry.tags:gsub("\n", " "))
  end

  table.insert(lines, "")
  table.insert(lines, separator(width))
  local detail_keys = require("refman").config.keys.detail
  local help_parts = {}
  if detail_keys.edit then
    table.insert(help_parts, "[" .. detail_keys.edit .. "] Edit")
  end
  if detail_keys.copy_citation then
    table.insert(help_parts, "[" .. detail_keys.copy_citation .. "] Copy Citation")
  end
  if detail_keys.delete then
    table.insert(help_parts, "[" .. detail_keys.delete .. "] Delete")
  end
  if detail_keys.close then
    table.insert(help_parts, "[" .. detail_keys.close .. "] Close")
  end
  table.insert(lines, table.concat(help_parts, "   "))

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modified = false
  vim.bo[buf].modifiable = false

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = math.min(82, vim.o.columns - 2),
    height = math.min(#lines + 2, vim.o.lines - 2),
    col = math.floor((vim.o.columns - math.min(82, vim.o.columns - 2)) / 2),
    row = 1,
    border = "rounded",
    style = "minimal",
  })

  local function close()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
  end

  if detail_keys.close then
    vim.keymap.set("n", detail_keys.close, close, { buffer = buf, silent = true })
  end
  if detail_keys.close_alt then
    vim.keymap.set("n", detail_keys.close_alt, close, { buffer = buf, silent = true })
  end

  if detail_keys.edit then
    vim.keymap.set("n", detail_keys.edit, function()
      close()
      M.edit_entry(entry, orig_buf)
    end, { buffer = buf, silent = true })
  end

  if detail_keys.copy_citation then
    vim.keymap.set("n", detail_keys.copy_citation, function()
      if entry.citation then
        local row, col = unpack(vim.api.nvim_win_get_cursor(0))
        local ob = orig_buf
        if vim.api.nvim_buf_is_valid(ob) then
          vim.bo[ob].modifiable = true
          vim.api.nvim_buf_set_text(ob, row - 1, col, row - 1, col, { entry.citation })
          vim.notify("Citation inserted: " .. entry.title, vim.log.levels.INFO)
        end
        close()
      end
    end, { buffer = buf, silent = true })
  end

  if detail_keys.delete then
    vim.keymap.set("n", detail_keys.delete, function()
      local confirm = vim.fn.confirm("Delete '" .. (entry.title or "this entry") .. "'?", "&Yes\n&No", 2)
      if confirm == 1 then
        if entry.id then
          backend().delete_entry(entry.id)
        end
        vim.notify("Entry deleted: " .. entry.title, vim.log.levels.INFO)
        close()
      end
    end, { buffer = buf, silent = true })
  end
end

---Open an editable buffer for entry fields.
---@param entry RefmanEntry
---@param orig_buf integer?
function M.edit_entry(entry, orig_buf)
  if not entry then
    vim.notify("[refman] Cannot edit: invalid entry", vim.log.levels.ERROR)
    return
  end

  orig_buf = orig_buf or vim.api.nvim_get_current_buf()

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "acwrite"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "dosini"
  pcall(vim.api.nvim_buf_set_name, buf, "refman://edit/" .. (entry.title or "entry"))

  local lines = {}
  local function add(s) table.insert(lines, s) end

  local function add_field(name, value)
    add("[" .. name .. "]")
    if value and value ~= "" then
      for _, line in ipairs(vim.split(value, "\n")) do
        add(line)
      end
    end
    add("")
  end

  add("# Edit the fields below (:w to save, q to discard)")
  add("")
  add("# ── Core ──")
  add("")
  add_field("author", entry.author)
  add_field("title", entry.title)
  add_field("year", entry.year)
  add_field("pub_type", entry.pub_type)
  add("")
  add("# ── Publication ──")
  add("")
  add_field("journal", entry.journal)
  add_field("volume", entry.volume)
  add_field("issue", entry.issue)
  add_field("pages", entry.pages)
  add_field("publisher", entry.publisher)
  add("")
  add("# ── Identifiers ──")
  add("")
  add_field("doi", entry.doi)
  add_field("isbn", entry.isbn)
  add_field("issn", entry.issn)
  add_field("url", entry.url)
  add_field("pmid", entry.pmid)
  add("")
  add("# ── Content ──")
  add("")
  add_field("citation", entry.citation)
  add_field("abstract", entry.abstract)
  add_field("notes", entry.notes)
  add_field("tags", entry.tags)
  add_field("keywords",
    entry.keywords and type(entry.keywords) == "table"
      and vim.json.encode(entry.keywords)
      or (entry.keywords or ""))

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modified = false

  local width = math.min(90, vim.o.columns - 2)
  local height = math.min(#lines + 4, vim.o.lines - 2)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    col = math.floor((vim.o.columns - width) / 2),
    row = 1,
    border = "rounded",
    style = "minimal",
  })

  local function close()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
  end

  local function parse_fields()
    local buf_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local fields = {}
    local current_field = nil
    local field_lines = {}

    for _, line in ipairs(buf_lines) do
      local name = line:match("^%[([%w_]+)%]$")
      if name then
        if current_field then
          while #field_lines > 0 and field_lines[#field_lines] == "" do
            table.remove(field_lines)
          end
          if #field_lines > 0 then
            fields[current_field] = table.concat(field_lines, "\n")
          end
        end
        current_field = name
        field_lines = {}
      elseif current_field and not line:match("^#") then
        table.insert(field_lines, line)
      end
    end

    if current_field then
      while #field_lines > 0 and field_lines[#field_lines] == "" do
        table.remove(field_lines)
      end
      if #field_lines > 0 then
        fields[current_field] = table.concat(field_lines, "\n")
      end
    end

    if fields.keywords then
      local ok, decoded = pcall(vim.json.decode, fields.keywords)
      if ok and type(decoded) == "table" then
        fields.keywords = decoded
      else
        fields.keywords = nil
      end
    end

    return fields
  end

  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = buf,
    callback = function()
      local fields = parse_fields()
      if not entry.id then
        vim.notify("[refman] Cannot save: entry has no id", vim.log.levels.ERROR)
        return
      end
      local ok, err = backend().update_entry(entry.id, fields)
      if ok then
        vim.bo[buf].modified = false
        local updated = vim.tbl_extend("force", vim.deepcopy(entry), fields)
        vim.notify("Entry updated: " .. (updated.title or entry.title), vim.log.levels.INFO)
        close()
        M.view_entry(updated, orig_buf)
      else
        vim.notify("[refman] " .. (err or "Failed to update entry"), vim.log.levels.ERROR)
      end
    end,
  })

  local detail_keys = require("refman").config.keys.detail

  if detail_keys.close then
    vim.keymap.set("n", detail_keys.close, function()
      close()
      M.view_entry(entry, orig_buf)
    end, { buffer = buf, silent = true })
  end
  if detail_keys.close_alt then
    vim.keymap.set("n", detail_keys.close_alt, function()
      close()
      M.view_entry(entry, orig_buf)
    end, { buffer = buf, silent = true })
  end
end

return M
