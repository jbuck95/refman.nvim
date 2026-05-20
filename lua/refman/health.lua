---@tag refman.health
local M = {}

function M.check()
  vim.health.start("refman.nvim")

  -- External dependencies
  if vim.fn.executable("curl") == 1 then
    vim.health.ok("curl")
  else
    vim.health.error("curl not found (required for DOI citations)")
  end

  if vim.fn.executable("fetch-metadata") == 1 then
    vim.health.ok("fetch-metadata")
  else
    vim.health.warn("fetch-metadata not found (required for ISBN citations)")
    vim.health.info("Install: pipx install <plugin-dir>/scripts/fetch-metadata")
  end

  if vim.fn.executable("pipx") == 1 then
    vim.health.ok("pipx (for fetch-metadata install)")
  elseif vim.fn.executable("pip") == 1 then
    vim.health.ok("pip (for fetch-metadata install)")
  else
    vim.health.warn("neither pipx nor pip found - install fetch-metadata manually")
  end

  if vim.fn.executable("fzf") == 1 then
    vim.health.ok("fzf")
  else
    vim.health.error("fzf not found (required for citation selection)")
  end

  if vim.fn.exists("*fzf#run") == 1 then
    vim.health.ok("fzf.vim loaded")
  else
    vim.health.info("fzf.vim lazy-loaded by lazy.nvim (triggers on first use)")
  end

  if vim.fn.executable("bash") == 1 then
    vim.health.ok("bash")
  else
    vim.health.warn("bash not found (used for fzf preview)")
  end

  -- Config validation
  vim.health.start("Configuration")
  local defaults = require("refman.config.defaults")

  local db_file = vim.fn.expand(defaults.db_file)
  if vim.fn.filereadable(db_file) == 1 then
    vim.health.ok("bibliography database: " .. db_file)
  else
    vim.health.info("bibliography database " .. db_file .. " will be auto-created on first use")
  end

  if type(defaults.log_level) == "string" then
    vim.health.ok("log_level = " .. defaults.log_level)
  else
    vim.health.error("log_level must be a string")
  end

  if type(defaults.doi_styles) == "table" and #defaults.doi_styles > 0 then
    vim.health.ok(string.format("%d DOI citation styles configured", #defaults.doi_styles))
  else
    vim.health.error("no DOI citation styles configured")
  end

  if type(defaults.isbn_styles) == "table" and #defaults.isbn_styles > 0 then
    vim.health.ok(string.format("%d ISBN citation styles configured", #defaults.isbn_styles))
  else
    vim.health.error("no ISBN citation styles configured")
  end

  -- API reachability
  vim.health.start("API reachability")
  local curl_ok = vim.fn.system(
    "curl -s -o /dev/null -w '%{http_code}' --connect-timeout 5 https://citation.doi.org/format 2>/dev/null"
  )
  if vim.v.shell_error == 0 and vim.trim(curl_ok) ~= "000" then
    vim.health.ok("citation.doi.org reachable (HTTP " .. vim.trim(curl_ok) .. ")")
  else
    vim.health.warn("citation.doi.org not reachable - DOI citations will fail")
  end
end

return M
