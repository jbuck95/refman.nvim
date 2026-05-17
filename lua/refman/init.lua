local M = {}

local log = require("refman.log")

local config = vim.tbl_extend("force", {
	db_file = vim.fn.expand("~/Documents/bibliography.md"),
}, require("refman.config"))

-- ── helpers ───────────────────────────────────────────────────────────────

local function exec_cmd(cmd)
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

local function get_visual_selection()
	local start_pos = vim.fn.getpos("'<")
	local end_pos = vim.fn.getpos("'>")
	local start_row, start_col = start_pos[2], start_pos[3]
	local end_row, end_col = end_pos[2], end_pos[3]
	local lines = vim.api.nvim_buf_get_lines(0, start_row - 1, end_row, false)
	if #lines == 0 then return "" end
	if #lines == 1 then
		lines[1] = lines[1]:sub(start_col, end_col)
	else
		lines[1] = lines[1]:sub(start_col)
		lines[#lines] = lines[#lines]:sub(1, end_col)
	end
	return table.concat(lines, " "):gsub("^%s+", ""):gsub("%s+$", "")
end

local function get_frontmatter_tags()
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
	local in_frontmatter = false
	local in_tags = false
	local tags = {}
	for _, line in ipairs(lines) do
		if line == "---" then
			if not in_frontmatter then in_frontmatter = true
			else break end
		elseif in_frontmatter then
			if line:match("^tags%s*:") then
				in_tags = true
			elseif in_tags then
				local tag = line:match("^%s*-%s*(.+)")
				if tag then table.insert(tags, tag)
				else in_tags = false end
			end
		end
	end
	return table.concat(tags, ", ")
end

-- ── DOI / ISBN citation fetching ──────────────────────────────────────────

function M.fetch_doi_citation(doi, style_config)
	doi = doi:gsub("^https?://doi%.org/", ""):gsub("^doi:", ""):gsub("^DOI:", "")
	local apis = {}
	for _, api in ipairs(style_config.apis or {}) do
		local url = api.url:gsub("{doi}", doi):gsub("{style}", api.style):gsub("{lang}", api.lang or "en-US")
		table.insert(apis, 'curl -s -L "' .. url .. '"')
	end
	for i, cmd in ipairs(apis) do
		log.debug(string.format("DOI API %d/%d for style '%s'", i, #apis, style_config.name or "unknown"))
		local result = exec_cmd(cmd)
		if result and result ~= "" and
			not result:match("Error") and
			not result:match("404") and
			not result:match("Not Found") and
			not result:match("<!DOCTYPE") and
			not result:match("^%s*$") and
			result:len() > 20 then
			result = result:gsub("&", "&"):gsub("<", "<"):gsub(">", ">")
				:gsub("&quot;", "\""):gsub("'", "'")
				:gsub("^%s+", ""):gsub("%s+$", "")
			log.debug("DOI fetch succeeded (API " .. i .. "/" .. #apis .. ")")
			return result
		end
		if result then
			local reason = ""
			if result:match("Error") then reason = "response contains 'Error'"
			elseif result:match("404") then reason = "HTTP 404"
			elseif result:match("Not Found") then reason = "response contains 'Not Found'"
			elseif result:match("<!DOCTYPE") then reason = "response is HTML"
			elseif result:match("^%s*$") then reason = "response is whitespace"
			elseif result:len() <= 20 then reason = "response too short (" .. result:len() .. " chars)"
			else reason = "unknown filter"
			end
			log.debug(string.format("DOI API %d rejected: %s", i, reason))
		end
	end

	log.debug("DOI " .. doi .. ": citation APIs exhausted, trying Crossref")
	local crossref_raw = exec_cmd('curl -s -L "https://api.crossref.org/works/' .. doi .. '"')
	if crossref_raw and crossref_raw ~= "" then
		local ok, data = pcall(vim.json.decode, crossref_raw)
		if ok and data and data.message then
			local msg = data.message
			local title = msg.title and msg.title[1] or "Unknown Title"
			local authors = {}
			if msg.author then
				for _, a in ipairs(msg.author) do
					table.insert(authors, (a.family or "") .. (a.given and ", " .. a.given or ""))
				end
			end
			local author_str = #authors > 0 and table.concat(authors, "; ") or "Unknown Author"
			local year = "n.d."
			local date_parts = msg["published-print"] or msg["published-online"] or msg["created"]
			if date_parts and date_parts["date-parts"] and date_parts["date-parts"][1] then
				year = tostring(date_parts["date-parts"][1][1] or "n.d.")
			end
			local publisher = msg.publisher or "Unknown Publisher"
			local journal = msg["container-title"] and msg["container-title"][1]
			local volume = msg.volume
			local pages = msg.page
			local template = style_config.template or "{authors}: {title}. {publisher} {year}."
			if journal then
				template = "{authors}: {title}. *{journal}* {volume}" .. (pages and ", " .. pages or "") .. ". {year}."
			end
			local citation = template
				:gsub("{authors}", author_str)
				:gsub("{title}", title)
				:gsub("{publisher}", publisher)
				:gsub("{journal}", journal or "")
				:gsub("{volume}", volume or "")
				:gsub("{year}", year)
			log.debug("DOI " .. doi .. ": Crossref fallback succeeded")
			return citation
		else
			log.debug("DOI " .. doi .. ": Crossref JSON parse failed")
		end
	end

	log.warn(string.format("DOI %s: all %d APIs + Crossref fallback failed for style '%s'", doi, #apis, style_config.name or "unknown"))
	return nil
end

function M.fetch_isbn_citation(isbn, style_config)
	isbn = isbn:gsub("[^0-9X]", "")
	local cmd = "fetch-metadata --isbn " .. isbn .. (log.level == "verbose" and " -v" or "")
	log.debug("ISBN lookup for " .. isbn .. " (style: " .. (style_config.name or "unknown") .. ")")
	local result = exec_cmd(cmd)
	if not result or result == "" then
		log.debug("ISBN " .. isbn .. ": fetch-metadata failed, trying OpenLibrary fallback")
		local ol_raw = exec_cmd('curl -s -L "https://openlibrary.org/api/books?bibkeys=ISBN:' .. isbn .. '&format=json&jscmd=data"')
		if ol_raw and ol_raw ~= "" then
			local ok, data = pcall(vim.json.decode, ol_raw)
			if ok and data then
				local key = "ISBN:" .. isbn
				local item = data[key]
				if item then
					local title = item.title or "Unknown Title"
					local authors_list = {}
					if item.authors then
						for _, a in ipairs(item.authors) do
							table.insert(authors_list, a.name or "Unknown Author")
						end
					end
					local authors = #authors_list > 0 and table.concat(authors_list, "; ") or "Unknown Author"
					local publisher = (item.publishers and item.publishers[1] and item.publishers[1].name) or "Unknown Publisher"
					local pub_date = item.publish_date or "Unknown Date"
					local year = pub_date:match("(%d%d%d%d)") or "n.d."
					local template = style_config.template or "{authors}. *{title}*. {publisher}, {year}."
					local citation = template:gsub("{authors}", authors):gsub("{title}", title)
						:gsub("{publisher}", publisher):gsub("{year}", year)
					log.debug("ISBN " .. isbn .. ": OpenLibrary fallback succeeded")
					return citation
				else
					log.debug("ISBN " .. isbn .. ": OpenLibrary returned no item for key " .. key)
				end
			else
				log.debug("ISBN " .. isbn .. ": OpenLibrary JSON parse failed")
			end
		end
		log.warn("ISBN " .. isbn .. ": fetch-metadata and OpenLibrary fallback both failed")
		return nil
	end
	log.debug("ISBN raw output (" .. style_config.name .. "):\n" .. result)
	local title = result:match("Title%s*:%s*(.-)\n") or result:match("title%s*:%s*(.-)\n") or "Unknown Title"
	local authors = result:match("Author%(s%)%s*:%s*(.-)\n") or result:match("author%s*:%s*(.-)\n") or result:match("Authors?%s*:%s*(.-)\n") or "Unknown Author"
	local publisher = result:match("Publisher%s*:%s*(.-)\n") or result:match("publisher%s*:%s*(.-)\n") or "Unknown Publisher"
	local pub_date = result:match("Published%s*:%s*(.-)\n") or result:match("published%s*:%s*(.-)\n") or "Unknown Date"
	local year = pub_date:match("(%d%d%d%d)") or "n.d."
	if title == "Unknown Title" then log.debug("ISBN " .. isbn .. ": could not parse title from output") end
	if authors == "Unknown Author" then log.debug("ISBN " .. isbn .. ": could not parse authors from output") end
	if publisher == "Unknown Publisher" then log.debug("ISBN " .. isbn .. ": could not parse publisher from output") end
	local template = style_config.template or "{authors}. *{title}*. {publisher}, {year}."
	local citation = template:gsub("{authors}", authors):gsub("{title}", title)
		:gsub("{publisher}", publisher):gsub("{year}", year)
	return citation
end

-- ── bibliography markdown database ────────────────────────────────────────

local function read_markdown_db()
	local file = io.open(config.db_file, "r")
	if not file then return {} end

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
		if author then current_author = author end

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
	local existing = read_markdown_db()
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

	local entry_text = string.format([[
### %s
**Citation:**
%s
**ISBN/DOI:** %s
**Tags:** %s
**Notes:**
]], entry.title, entry.citation, entry.isbn_doi or "", entry.tags or "")

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

-- ── user commands ─────────────────────────────────────────────────────────

function M.import_current_line()
	local line = vim.api.nvim_get_current_line()
	if line == "" then
		vim.notify("No line to import", vim.log.levels.WARN)
		return
	end

	local entry = {}

	local author_match = line:match("^([^,]+,%s*[^:%.]+)")
	if author_match then
		entry.author = author_match:match("^%s*(.-)%s*$")
	else
		entry.author = "Unknown Author"
	end

	local title_match = line:match("%*([^%*]+)%*") or
		line:match("\"([^\"]+)\"") or
		line:match("^[^:]+:%s*(.-)%.") or
		line:match("^[^%.]+%.%s*(.-)%.")
	entry.title = title_match or "Unknown Title"
	entry.citation = line:match("^%s*(.-)%s*$")

	if M.add_entry(entry) then
		vim.notify("Entry imported: " .. entry.title, vim.log.levels.INFO)
	else
		vim.notify("Failed to add entry", vim.log.levels.ERROR)
	end
end

local function build_fzf_entries(entries)
	table.sort(entries, function(a, b)
		local aa = (a.author or ""):lower()
		local ba = (b.author or ""):lower()
		if aa ~= ba then return aa < ba end
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
		table.insert(fzf_entries, string.format("%d\x1f%s - %s\x1f%s\x1f%s\x1f%s",
			i, display_author, entry.title,
			entry.citation or "", entry.isbn_doi or "", entry.tags or ""))
	end
	return fzf_entries
end

function M.export_citation()
	local entries = read_markdown_db()
	if #entries == 0 then
		vim.notify("No entries in bibliography database", vim.log.levels.WARN)
		return
	end

	local preview_script = "/tmp/bib_preview.sh"
	local f = io.open(preview_script, "w")
	f:write([=[#!/usr/bin/env bash
IFS=$'\x1f' read -r -a fields <<< "$*"
printf "\033[1mCitation:\033[0m\n%s\n\n\033[1mISBN/DOI:\033[0m\n%s\n\n\033[1mTags:\033[0m\n%s\n" "${fields[2]}" "${fields[3]}" "${fields[4]}"
]=])
	f:close()
	os.execute("chmod +x " .. preview_script)

	local fzf_entries = build_fzf_entries(entries)

	vim.fn['fzf#run']({
		source = fzf_entries,
		sink = function(line)
			local entry_num = tonumber(line:match("^(%d+)\x1f"))
			if entry_num and entries[entry_num] then
				local citation = entries[entry_num].citation
				local row, col = unpack(vim.api.nvim_win_get_cursor(0))
				vim.api.nvim_buf_set_text(0, row-1, col, row-1, col, {citation})
				vim.notify("Citation inserted: " .. entries[entry_num].title, vim.log.levels.INFO)
			end
		end,
		options = {
			'--prompt', 'Select Citation> ',
			'--delimiter', '\x1f',
			'--with-nth', '2',
			'--preview-window', 'down:40%',
			'--preview', '/tmp/bib_preview.sh {} | fold -s -w $FZF_PREVIEW_COLUMNS',
			'--height', '70%',
			'--layout', 'reverse',
			'--border'
		},
	})
end

local function format_bibliography(picked)
	table.sort(picked, function(a, b)
		local aa = (a.author or ""):lower()
		local ba = (b.author or ""):lower()
		if aa ~= ba then return aa < ba end
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

function M.export_citations_multi()
	local entries = read_markdown_db()
	if #entries == 0 then
		vim.notify("No entries in bibliography database", vim.log.levels.WARN)
		return
	end

	local fzf_entries = build_fzf_entries(entries)

	local original_pos = vim.api.nvim_win_get_cursor(0)

	vim.fn['fzf#run']({
		source = fzf_entries,
		['sink*'] = function(selected)
			if not selected or #selected == 0 then return end
			local picked = {}
			for _, line in ipairs(selected) do
				local entry_num = tonumber(line:match("^(%d+)\x1f"))
				if entry_num and entries[entry_num] then
					table.insert(picked, entries[entry_num])
				end
			end
			local bib_lines = format_bibliography(picked)
			local row = original_pos[1]
			for i, l in ipairs(bib_lines) do
				vim.api.nvim_buf_set_lines(0, row, row, false, { l })
				row = row + 1
				if i < #bib_lines then
					vim.api.nvim_buf_set_lines(0, row, row, false, { "" })
					row = row + 1
				end
			end
			vim.notify("Inserted " .. #picked .. " citations", vim.log.levels.INFO)
		end,
		options = {
			'--prompt', 'Select Citations (Tab=multi)> ',
			'--multi',
			'--delimiter', '\x1f',
			'--with-nth', '2',
			'--height', '70%',
			'--layout', 'reverse',
			'--border'
		},
	})
end

function M.open_database()
	vim.cmd("edit " .. config.db_file)
end

-- ── interactive citation conversion (floating TUI) ───────────────────────

local function clear_buf_keymaps(buf)
	local maps = vim.api.nvim_buf_get_keymap(buf, "n")
	for _, m in ipairs(maps) do
		pcall(vim.keymap.del, "n", m.lhs, { buffer = buf })
	end
end

local function citation_tui(id_type, identifier)
	local cursor_pos = vim.api.nvim_win_get_cursor(0)
	local styles = id_type == "doi" and config.doi_styles or config.isbn_styles

	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "wipe"

	local win = nil
	local citation = nil
	local max_width = math.min(80, vim.o.columns - 8)

	local function set_content(lines)
		vim.bo[buf].modifiable = true
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
		vim.bo[buf].modifiable = false

		local max_line_len = 0
		for _, l in ipairs(lines) do
			if #l > max_line_len then max_line_len = #l end
		end
		local w = math.max(50, math.min(max_width + 8, max_line_len + 4))
		local h = math.min(vim.o.lines - 2, #lines + 2)
		local col = math.floor((vim.o.columns - w) / 2)
		local row = math.floor((vim.o.lines - h) / 2 - 1)

		if win then
			vim.api.nvim_win_set_config(win, { relative = "editor", width = w, height = h, col = col, row = row })
			vim.api.nvim_set_current_win(win)
		else
			win = vim.api.nvim_open_win(buf, true, {
				relative = "editor", width = w, height = h, col = col, row = row,
				border = "rounded", style = "minimal",
			})
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

	local function already_in_db(cit)
		local author = cit:match("^(.-)%s*:") or "Unknown"
		local title = cit:match(":%s*(.-)%s*[%.;]") or cit:match(":%s*(.+)$") or "Unknown"
		local entries = read_markdown_db()
		for _, e in ipairs(entries) do
			if (e.author or ""):lower():match("^%s*(.-)%s*$") == author:lower():match("^%s*(.-)%s*$")
				and (e.title or ""):lower():match("^%s*(.-)%s*$") == title:lower():match("^%s*(.-)%s*$") then
				return true
			end
		end
		return false
	end

	local function do_insert()
		local mod = vim.bo.modifiable
		vim.bo.modifiable = true
		vim.api.nvim_buf_set_lines(0, cursor_pos[1], cursor_pos[1], false, { citation })
		vim.bo.modifiable = mod
	end

	local function do_save()
		local author = citation:match("^(.-)%s*:") or "Unknown"
		local title = citation:match(":%s*(.-)%s*[%.;]") or citation:match(":%s*(.+)$") or "Unknown"
		M.add_entry({
			author = author, title = title, citation = citation,
			isbn_doi = identifier, tags = get_frontmatter_tags(),
		})
		return title
	end

	local show_result
	local show_styles
	local on_style_selected

	show_result = function()
		local lines = { "Identifier: " .. identifier, "" }

		if citation then
			local wrapped = wrap_text(citation, max_width)
			for _, l in ipairs(wrapped) do table.insert(lines, l) end
			table.insert(lines, "")

			local exists = already_in_db(citation)

			clear_buf_keymaps(buf)
			if exists then
				table.insert(lines, "[Already in bibliography]")
				table.insert(lines, "")
				table.insert(lines, "[e] Edit   [q] Cancel")

				vim.keymap.set("n", "e", function()
					do_insert()
					vim.api.nvim_win_close(win, true)
					local title = citation:match(":%s*(.-)%s*[%.;]") or citation:match(":%s*(.+)$") or "Unknown"
					M.open_database()
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
					M.open_database()
					vim.fn.search(vim.fn.escape(title, ".*[]~\\"), "w")
				end, { buffer = buf })
			end
		else
			table.insert(lines, "Could not resolve " .. id_type:upper())
			table.insert(lines, "")
			table.insert(lines, "[r] Retry   [q] Cancel")

			clear_buf_keymaps(buf)
			vim.keymap.set("n", "r", function() show_styles() end, { buffer = buf })
		end
		vim.keymap.set("n", "q", function() vim.api.nvim_win_close(win, true) end, { buffer = buf })
		set_content(lines)
	end

	show_styles = function()
		local lines = { "Identifier: " .. identifier, "", "Select citation style:" }
		for i, s in ipairs(styles) do
			table.insert(lines, string.format("  %d. %s", i, s.name))
		end

		clear_buf_keymaps(buf)
		for i = 1, #styles do
			vim.keymap.set("n", tostring(i), function() on_style_selected(i) end, { buffer = buf, nowait = true })
		end
		vim.keymap.set("n", "<CR>", function()
			local line = vim.api.nvim_get_current_line()
			local idx = tonumber(line:match("^%s*(%d+)%."))
			if idx and idx <= #styles then on_style_selected(idx) end
		end, { buffer = buf })
		vim.keymap.set("n", "q", function() vim.api.nvim_win_close(win, true) end, { buffer = buf })

		set_content(lines)
		vim.api.nvim_win_set_cursor(win, { 3, 0 })
	end

	on_style_selected = function(idx)
		set_content({ "Identifier: " .. identifier, "", "Fetching citation...", "", "Style: " .. styles[idx].name })
		vim.cmd("redraw")

		local ok, result = pcall(
			id_type == "doi" and M.fetch_doi_citation or M.fetch_isbn_citation,
			identifier, styles[idx]
		)
		if not ok then
			log.error("fetch crash: " .. tostring(result))
		end
		citation = ok and result or nil
		show_result()
	end

	show_styles()
end

function M.convert_doi_citation()
	local selection = get_visual_selection()
	if selection == "" then return end
	citation_tui("doi", selection)
end

function M.convert_isbn_citation()
	local selection = get_visual_selection()
	if selection == "" then return end
	citation_tui("isbn", selection)
end

-- ── setup ─────────────────────────────────────────────────────────────────

function M.setup(opts)
	config = vim.tbl_extend("force", config, opts or {})
	log.level = config.log_level or "error"

	if vim.fn.filereadable(config.db_file) == 0 then
		local file = io.open(config.db_file, "w")
		if file then
			file:write("# Bibliography Database\n\n")
			file:write("<!-- Use :RefImport to add entries, :RefExport to insert citations, :RefOpen to edit -->\n\n")
			file:close()
		end
	end

	vim.api.nvim_create_user_command("DOI", M.convert_doi_citation, { range = true })
	vim.api.nvim_create_user_command("ISBN", M.convert_isbn_citation, { range = true })
	vim.api.nvim_create_user_command("RefImport", M.import_current_line, {})
	vim.api.nvim_create_user_command("RefOpen", M.open_database, {})
	vim.api.nvim_create_user_command("RefExport", M.export_citation, {})
	vim.api.nvim_create_user_command("RefMulti", M.export_citations_multi, {})
	vim.api.nvim_create_user_command("RefLog", log.open_log, {})

	_G.doi_convert = M.convert_doi_citation
	_G.isbn_convert = M.convert_isbn_citation
end

return M
