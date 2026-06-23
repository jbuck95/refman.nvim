---@tag refman.db
local M = {}

local log = require("refman.log")
local config
local backend

function M.set_config(cfg)
  config = cfg
end

function M.get_backend()
  if backend then
    return backend
  end
  backend = require("refman.db.sqlite")
  backend.set_config(config)
  return backend
end

-- ── utility ──────────────────────────────────────────────────────────────────

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

-- ── backend delegation ───────────────────────────────────────────────────────

function M.get_all_entries()
  return M.get_backend().read_all()
end

function M.add_entry(entry)
  return M.get_backend().add_entry(entry)
end

function M.get_entry(id)
  return M.get_backend().get_entry(id)
end

function M.update_entry(id, fields)
  return M.get_backend().update_entry(id, fields)
end

function M.delete_entry(id)
  return M.get_backend().delete_entry(id)
end

function M.open_database()
  return M.get_backend().open_database()
end

function M.search_entries(query)
  return M.get_backend().search_entries(query)
end

return M
