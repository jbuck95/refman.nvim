---@tag refman.db
local M = {}

local log = require("refman.log")
local config

---@param cfg RefmanConfig
function M.set_config(cfg)
  config = cfg
end

-- ── helpers ──────────────────────────────────────────────────────────────────

function M.exec_cmd(cmd)
  log.debug("exec: " .. cmd)
  local stderr_tmp = os.tmpname()
  local stdout = vim.fn.system(cmd .. " 2>" .. stderr_tmp)
  local exit_code = vim.v.shell_error

  local f = io.open(stderr_tmp)
  if f then
    local stderr_out = f:read("*a")
    f:close()
    if stderr_out and stderr_out ~= "" then
      log.debug("stderr: " .. stderr_out:gsub("\n+$", ""):gsub("\n", " | "))
    end
  end
  os.remove(stderr_tmp)

  if exit_code ~= 0 then
    log.warn(string.format("exit %d: %s", exit_code, cmd))
  end
  if not stdout or stdout == "" then
    if exit_code == 0 then
      log.debug("no stdout (exit 0): " .. cmd)
    end
    return ""
  end
  return stdout:gsub("^%s+", ""):gsub("%s+$", ""):gsub("\n$", "")
end

function M.get_visual_selection()
  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")
  local start_row, start_col = start_pos[2], start_pos[3]
  local end_row, end_col = end_pos[2], end_pos[3]
  local lines = vim.api.nvim_buf_get_lines(0, start_row - 1, end_row, false)
  if #lines == 0 then
    return ""
  end
  if #lines == 1 then
    lines[1] = lines[1]:sub(start_col, end_col)
  else
    lines[1] = lines[1]:sub(start_col)
    lines[#lines] = lines[#lines]:sub(1, end_col)
  end
  return table.concat(lines, " "):gsub("^%s+", ""):gsub("%s+$", "")
end

function M.get_frontmatter_tags()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local in_frontmatter = false
  local in_tags = false
  local tags = {}
  for _, line in ipairs(lines) do
    if line == "---" then
      if not in_frontmatter then
        in_frontmatter = true
      else
        break
      end
    elseif in_frontmatter then
      if line:match("^tags%s*:") then
        in_tags = true
      elseif in_tags then
        local tag = line:match("^%s*-%s*(.+)")
        if tag then
          table.insert(tags, tag)
        else
          in_tags = false
        end
      end
    end
  end
  return table.concat(tags, ", ")
end

-- ── bibliography markdown database ──────────────────────────────────────────

function M.read_markdown_db()
  local file = io.open(config.db_file, "r")
  if not file then
    return {}
  end

  local content = file:read("*all")
  file:close()

  local entries = {}
  local current_author = nil
  local current_entry = nil
  local waiting_for_citation = false
  local waiting_for_isbn = false
  local waiting_for_tags = false

  for line in content:gmatch("[^\n]*") do
    local author = line:match("^## (.+)")
    if author then
      current_author = author
    end

    local title = line:match("^### (.+)")
    if title and current_author then
      if current_entry and current_entry.title then
        table.insert(entries, current_entry)
      end
      current_entry = { author = current_author, title = title }
      waiting_for_citation = false
      waiting_for_isbn = false
      waiting_for_tags = false
    end

    if line:match("^%*%*Citation:%*%*") and current_entry then
      local inline = line:match("^%*%*Citation:%*%*%s*(.+)")
      if inline then
        current_entry.citation = inline
      else
        waiting_for_citation = true
      end
    elseif waiting_for_citation and line:match("^%s*[^%s*].*") and current_entry then
      current_entry.citation = line:match("^%s*(.-)%s*$")
      waiting_for_citation = false
    end

    if line:match("^%*%*ISBN/DOI:%*%*") and current_entry then
      local inline = line:match("^%*%*ISBN/DOI:%*%*%s*(.+)")
      if inline then
        current_entry.isbn_doi = inline
      else
        waiting_for_isbn = true
      end
    elseif waiting_for_isbn and current_entry then
      current_entry.isbn_doi = line:match("^%s*(.-)%s*$")
      waiting_for_isbn = false
    end

    if line:match("^%*%*Tags:%*%*") and current_entry then
      local inline = line:match("^%*%*Tags:%*%*%s*(.+)")
      if inline then
        current_entry.tags = inline
      else
        waiting_for_tags = true
      end
    elseif waiting_for_tags and current_entry then
      current_entry.tags = line:match("^%s*(.-)%s*$")
      waiting_for_tags = false
    end
  end

  if current_entry and current_entry.title then
    table.insert(entries, current_entry)
  end

  return entries
end

function M.add_entry(entry)
  local existing = M.read_markdown_db()
  for _, e in ipairs(existing) do
    if (e.author or ""):lower():match("^%s*(.-)%s*$") == (entry.author or ""):lower():match("^%s*(.-)%s*$")
      and (e.title or ""):lower():match("^%s*(.-)%s*$") == (entry.title or ""):lower():match("^%s*(.-)%s*$") then
      vim.notify("Entry already exists: " .. entry.title, vim.log.levels.WARN)
      return false
    end
  end

  local file = io.open(config.db_file, "r")
  local content = ""
  if file then
    content = file:read("*all")
    file:close()
  end

  local escaped_author = entry.author:gsub("[%(%)%.%+%-%*%?%[%]%^%$%%]", "%%%1")

  local entry_text = string.format(
    [[
### %s
**Citation:**
%s
**ISBN/DOI:** %s
**Tags:** %s
**Notes:**
]],
    entry.title,
    entry.citation,
    entry.isbn_doi or "",
    entry.tags or ""
  )

  local author_pattern = "\n## " .. escaped_author .. "\n"
  local author_start = content:find(author_pattern, 1, true)

  if author_start then
    local next_author = content:find("\n## ", author_start + #author_pattern)
    local insert_pos = next_author or (#content + 1)
    content = content:sub(1, insert_pos - 1) .. entry_text .. "\n" .. content:sub(insert_pos)
  else
    content = content .. "\n## " .. entry.author .. "\n" .. entry_text
  end

  file = io.open(config.db_file, "w")
  if file then
    file:write(content)
    file:close()
    return true
  end
  return false
end

function M.open_database()
  vim.cmd("edit " .. config.db_file)
end

function M.build_fzf_entries(entries)
  table.sort(entries, function(a, b)
    local aa = (a.author or ""):lower()
    local ba = (b.author or ""):lower()
    if aa ~= ba then
      return aa < ba
    end
    return (a.title or ""):lower() < (b.title or ""):lower()
  end)

  local fzf_entries = {}
  local prev_author = nil
  for i, entry in ipairs(entries) do
    local display_author = entry.author
    if prev_author and prev_author:lower() == (entry.author or ""):lower() then
      display_author = "---"
    else
      prev_author = entry.author
    end
    table.insert(
      fzf_entries,
      string.format(
        "%d\x1f%s - %s\x1f%s\x1f%s\x1f%s",
        i,
        display_author,
        entry.title,
        entry.citation or "",
        entry.isbn_doi or "",
        entry.tags or ""
      )
    )
  end
  return fzf_entries
end

function M.format_bibliography(picked)
  table.sort(picked, function(a, b)
    local aa = (a.author or ""):lower()
    local ba = (b.author or ""):lower()
    if aa ~= ba then
      return aa < ba
    end
    return (a.title or ""):lower() < (b.title or ""):lower()
  end)

  local lines = {}
  local prev_author = nil
  for _, entry in ipairs(picked) do
    local cit = entry.citation or ""
    if prev_author and prev_author:lower() == (entry.author or ""):lower() then
      local pattern = "^" .. vim.pesc(entry.author) .. "%."
      local replaced = cit:gsub(pattern, "---------", 1)
      if replaced == cit then
        pattern = "^" .. vim.pesc(entry.author) .. ":"
        replaced = cit:gsub(pattern, "---------", 1)
      end
      cit = replaced
    else
      prev_author = entry.author
    end
    table.insert(lines, cit)
  end
  return lines
end

return M
