---@tag refman.citation
local M = {}

local log = require("refman.log")
local db = require("refman.db")

-- ── citation cache ────────────────────────────────────────────────────────────

local plugin_root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h")
local fetch_metadata_cmd = "PYTHONPATH="
  .. plugin_root
  .. "/scripts/fetch-metadata/src python3 -m metadata.cli"

local cache_file = vim.fn.stdpath("cache") .. "/refman-cache.json"

local function load_cache()
  local f = io.open(cache_file, "r")
  if not f then
    return {}
  end
  local content = f:read("*all")
  f:close()
  if not content or content == "" then
    return {}
  end
  local ok, data = pcall(vim.json.decode, content)
  return (ok and data) and data or {}
end

local function save_cache(cache)
  local f = io.open(cache_file, "w")
  if f then
    f:write(vim.json.encode(cache))
    f:close()
  end
end

local function cache_key(identifier, style_name)
  return identifier .. "::" .. style_name
end

-- ── DOI citation fetching ────────────────────────────────────────────────────

---@param doi string
---@param style_config RefmanStyle
---@return string|nil
function M.fetch_doi_citation(doi, style_config)
  doi = doi:gsub("^https?://doi%.org/", "")
    :gsub("^doi:", "")
    :gsub("^DOI:", "")
    :gsub("[.,;:)%]%[\"?!']+$", "")
  local ckey = cache_key(doi, style_config.name)
  local cache = load_cache()
  if cache[ckey] then
    log.debug("DOI cache hit: " .. ckey)
    return cache[ckey]
  end
  local apis = {}
  for _, api in ipairs(style_config.apis or {}) do
    local url = api.url:gsub("{doi}", doi):gsub("{style}", api.style):gsub("{lang}", api.lang or "en-US")
    table.insert(apis, 'curl -s -L "' .. url .. '"')
  end
  for i, cmd in ipairs(apis) do
    log.debug(string.format("DOI API %d/%d for style '%s'", i, #apis, style_config.name or "unknown"))
    local result = db.exec_cmd(cmd)
    if
      result
      and result ~= ""
      and not result:match("Error")
      and not result:match("404")
      and not result:match("Not Found")
      and not result:match("<!DOCTYPE")
      and not result:match("^%s*$")
      and result:len() > 20
    then
      if not result:match("%d%d%d%d") then
        log.debug("DOI API " .. i .. " rejected: no year found in result")
      else
        result = result
          :gsub("&", "&")
          :gsub("<", "<")
          :gsub(">", ">")
          :gsub("&quot;", "\"")
          :gsub("'", "'")
          :gsub("^%s+", "")
          :gsub("%s+$", "")
        log.debug("DOI fetch succeeded (API " .. i .. "/" .. #apis .. ")")
        cache[ckey] = result
        save_cache(cache)
        return result
      end
    end
    if result then
      local reason = ""
      if result:match("Error") then
        reason = "response contains 'Error'"
      elseif result:match("404") then
        reason = "HTTP 404"
      elseif result:match("Not Found") then
        reason = "response contains 'Not Found'"
      elseif result:match("<!DOCTYPE") then
        reason = "response is HTML"
      elseif result:match("^%s*$") then
        reason = "response is whitespace"
      elseif result:len() <= 20 then
        reason = "response too short (" .. result:len() .. " chars)"
      else
        reason = "unknown filter"
      end
      log.debug(string.format("DOI API %d rejected: %s", i, reason))
    end
  end

  log.debug("DOI " .. doi .. ": citation APIs exhausted, trying Crossref")
  local crossref_raw = db.exec_cmd('curl -s -L "https://api.crossref.org/works/' .. doi .. '"')
  if crossref_raw and crossref_raw ~= "" then
    ---@diagnostic disable-next-line: redefined-local
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
      local template = style_config.template
        or "{authors}: {title}. {publisher} {year}."
      if journal then
        template = "{authors}: {title}. *{journal}* {volume}"
          .. (pages and ", " .. pages or "")
          .. ". {year}."
      end
      local citation = template
        :gsub("{authors}", author_str)
        :gsub("{title}", title)
        :gsub("{publisher}", publisher)
        :gsub("{journal}", journal or "")
        :gsub("{volume}", volume or "")
        :gsub("{year}", year)
      log.debug("DOI " .. doi .. ": Crossref fallback succeeded (not cached)")
      return citation
    else
      log.debug("DOI " .. doi .. ": Crossref JSON parse failed")
    end
  end

  log.warn(
    string.format(
      "DOI %s: all %d APIs + Crossref fallback failed for style '%s'",
      doi,
      #apis,
      style_config.name or "unknown"
    )
  )
  return nil
end

-- ── ISBN citation fetching ───────────────────────────────────────────────────

---@param isbn string
---@param style_config RefmanStyle
---@return string|nil
function M.fetch_isbn_citation(isbn, style_config)
  isbn = isbn:gsub("[^0-9X]", "")
  local ckey = cache_key(isbn, style_config.name)
  local cache = load_cache()
  if cache[ckey] then
    log.debug("ISBN cache hit: " .. ckey)
    return cache[ckey]
  end
  local cmd = fetch_metadata_cmd .. " --isbn " .. isbn .. (log.level == "verbose" and " -v" or "")
  log.debug("ISBN lookup for " .. isbn .. " (style: " .. (style_config.name or "unknown") .. ")")
  local result = db.exec_cmd(cmd)
  if not result or result == "" then
    log.debug("ISBN " .. isbn .. ": fetch-metadata failed, trying OpenLibrary fallback")
    local ol_raw = db.exec_cmd(
      'curl -s -L "https://openlibrary.org/api/books?bibkeys=ISBN:'
        .. isbn
        .. '&format=json&jscmd=data"'
    )
    if ol_raw and ol_raw ~= "" then
      ---@diagnostic disable-next-line: redefined-local
      local ok, data = pcall(vim.json.decode, ol_raw)
      if ok and data then
        local key = "ISBN:" .. isbn
        local item = data[key]
        if item then
          local title = item.title or "Unknown Title"
          if item.subtitle then
            title = title .. ": " .. item.subtitle
          end
          local authors_list = {}
          if item.authors then
            for _, a in ipairs(item.authors) do
              table.insert(authors_list, a.name or "Unknown Author")
            end
          end
          if #authors_list <= 1 and item.by_statement then
            local bs = item.by_statement:gsub("%.$", "")
            for _, sep in ipairs({"/", "; ", ";", ", "}) do
              local parts = {}
              for part in bs:gmatch("[^" .. sep .. "]+") do
                part = part:match("^%s*(.-)%s*$")
                if part ~= "" then
                  table.insert(parts, part)
                end
              end
              if #parts > #authors_list then
                authors_list = parts
                break
              end
            end
          end
          local authors = #authors_list > 0 and table.concat(authors_list, "; ") or "Unknown Author"
          local publisher = (item.publishers and item.publishers[1] and item.publishers[1].name)
            or "Unknown Publisher"
          local pub_date = item.publish_date or "Unknown Date"
          local year = pub_date:match("(%d%d%d%d)") or "n.d."
          local template = style_config.template or "{authors}. *{title}*. {publisher}, {year}."
          local citation = template
            :gsub("{authors}", authors)
            :gsub("{title}", title)
            :gsub("{publisher}", publisher)
            :gsub("{year}", year)
          log.debug("ISBN " .. isbn .. ": OpenLibrary fallback succeeded (not cached)")
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
  local title = result:match("Title%s*:%s*(.-)\n")
    or result:match("title%s*:%s*(.-)\n")
    or "Unknown Title"
  local authors = result:match("Author%(s%)%s*:%s*(.-)\n")
    or result:match("author%s*:%s*(.-)\n")
    or result:match("Authors?%s*:%s*(.-)\n")
    or "Unknown Author"
  local publisher = result:match("Publisher%s*:%s*(.-)\n")
    or result:match("publisher%s*:%s*(.-)\n")
    or "Unknown Publisher"
  local pub_date = result:match("Published%s*:%s*(.-)\n")
    or result:match("published%s*:%s*(.-)\n")
    or "Unknown Date"
  local year = pub_date:match("(%d%d%d%d)") or "n.d."
  if title == "Unknown Title" then
    log.debug("ISBN " .. isbn .. ": could not parse title from output")
  end
  if authors == "Unknown Author" then
    log.debug("ISBN " .. isbn .. ": could not parse authors from output")
  end
  if publisher == "Unknown Publisher" then
    log.debug("ISBN " .. isbn .. ": could not parse publisher from output")
  end
  local template = style_config.template or "{authors}. *{title}*. {publisher}, {year}."
  local citation = template
    :gsub("{authors}", authors)
    :gsub("{title}", title)
    :gsub("{publisher}", publisher)
    :gsub("{year}", year)
  cache[ckey] = citation
  save_cache(cache)
  return citation
end

---Clear the citation cache file.
function M.clear_cache()
  os.remove(cache_file)
  log.info("Citation cache cleared")
end

return M
