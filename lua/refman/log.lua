local M = {}

M.level = "error"

local log_file = vim.fn.stdpath("cache") .. "/refman.log"

local function now()
	return os.date("%Y-%m-%d %H:%M:%S")
end

local function write_line(level_str, msg)
	local line = string.format("[%s] [%s] %s\n", now(), level_str, msg)
	local file = io.open(log_file, "a")
	if file then
		file:write(line)
		file:close()
	end
end

function M.debug(msg)
	if M.level ~= "verbose" then return end
	write_line("DEBUG", msg)
end

function M.info(msg)
	write_line("INFO", msg)
	vim.schedule(function()
		vim.notify("[refman] " .. msg, vim.log.levels.INFO)
	end)
end

function M.warn(msg)
	write_line("WARN", msg)
	vim.schedule(function()
		vim.notify("[refman] " .. msg, vim.log.levels.WARN)
	end)
end

function M.error(msg)
	write_line("ERROR", msg)
	vim.schedule(function()
		vim.notify("[refman] " .. msg, vim.log.levels.ERROR)
	end)
end

function M.open_log()
	local path = log_file
	if vim.fn.filereadable(path) == 0 then
		vim.notify("[refman] No log file yet", vim.log.levels.WARN)
		return
	end
	vim.cmd("tabedit " .. vim.fn.fnameescape(path))
	vim.bo.bufhidden = "wipe"
	vim.bo.buftype = "nofile"
	vim.api.nvim_buf_set_keymap(0, "n", "q", "<cmd>close<CR>", { noremap = true, silent = true })
end

return M
