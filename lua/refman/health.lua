local M = {}

function M.check()
	vim.health.start("refman.nvim")

	if vim.fn.executable("curl") == 1 then
		vim.health.ok("curl")
	else
		vim.health.error("curl not found (required for DOI citations)")
	end

	if vim.fn.executable("fetch-metadata") == 1 then
		vim.health.ok("fetch-metadata")
	else
		vim.health.warn("fetch-metadata not found (required for ISBN citations)")
	end

	if vim.fn.executable("fzf") == 1 then
		vim.health.ok("fzf (global)")
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

	if vim.fn.filereadable(vim.fn.expand("~/Documents/bibliography.md")) == 1 then
		vim.health.ok("~/Documents/bibliography.md")
	else
		vim.health.info("~/Documents/bibliography.md will be auto-created on first use")
	end

	vim.health.start("API reachability")
	local curl_ok = vim.fn.system("curl -s -o /dev/null -w '%{http_code}' --connect-timeout 5 https://citation.doi.org/format 2>/dev/null")
	if vim.v.shell_error == 0 and vim.trim(curl_ok) ~= "000" then
		vim.health.ok("citation.doi.org reachable (HTTP " .. vim.trim(curl_ok) .. ")")
	else
		vim.health.warn("citation.doi.org not reachable – DOI citations will fail")
	end
end

return M
