---@tag refman.health
local M = {}

function M.check()
  vim.health.start("refman.nvim")

  -- External dependencies
  if vim.fn.executable("curl") == 1 then
    vim.health.ok("curl")
  else
    vim.health.error("curl not found (required for API calls)")
  end

  if pcall(require, "telescope") then
    vim.health.ok("telescope.nvim (required for :RefBrowse, :RefSearch, :RefOpen)")
  else
    vim.health.error("telescope.nvim not installed -- required for browsing bibliography")
  end

  -- SQLite
  vim.health.start("SQLite backend")
  local defaults = require("refman.config.defaults")
  if vim.fn.executable("sqlite3") == 1 then
    vim.health.ok("sqlite3 CLI available")
    local sqlite_path = defaults.db_file:gsub("%.md$", ".sqlite3")
    if vim.fn.filereadable(sqlite_path) == 1 then
      vim.health.ok("SQLite database: " .. sqlite_path)
    else
      vim.health.info("SQLite database will be created on first use: " .. sqlite_path)
    end
  else
    vim.health.error("sqlite3 CLI not found")
  end

  -- CSL (now mandatory)
  vim.health.start("CSL formatting (citation-js)")
  if vim.fn.executable("node") == 1 then
    vim.health.ok("node")
    local csl = require("refman.csl")
    if csl.is_available() then
      vim.health.ok("citation-js packages available")
    else
      vim.health.error("citation-js packages not found (run: npm install -g @citation-js/core @citation-js/plugin-csl)")
    end
  else
    vim.health.error("node not found -- required for CSL formatting (citation-js)")
  end

  if defaults.csl and defaults.csl.styles then
    local styles_ok = 0
    local styles_missing = 0
    for _, s in ipairs(defaults.csl.styles) do
      if vim.fn.filereadable(s.path) == 1 then
        styles_ok = styles_ok + 1
      else
        styles_missing = styles_missing + 1
        vim.health.warn("CSL style file not found: " .. s.path .. " (" .. s.name .. ")")
      end
    end
    if styles_ok > 0 then
      vim.health.ok(string.format("%d CSL styles available", styles_ok))
    end
    if styles_missing == #defaults.csl.styles then
      vim.health.error("no CSL style files found -- citations will fail")
    end
  else
    vim.health.error("no CSL styles configured in csl.styles")
  end

  if defaults.csl and defaults.csl.default_style then
    vim.health.info("default CSL style: " .. defaults.csl.default_style)
  end

  if defaults.csl and defaults.csl.cite_mode then
    vim.health.info("cite mode: " .. defaults.csl.cite_mode)
  end

  -- Source APIs
  vim.health.start("Source APIs")
  if defaults.source_apis then
    for name, opts in pairs(defaults.source_apis) do
      if opts.enabled then
        vim.health.info(string.format("%s enabled", name))
      end
    end
  end

  -- Config validation
  vim.health.start("Configuration")

  if type(defaults.log_level) == "string" then
    vim.health.ok("log_level = " .. defaults.log_level)
  else
    vim.health.error("log_level must be a string")
  end
end

return M
