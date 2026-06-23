---@tag refman.source.crossref
---Fetches rich metadata from the Crossref REST API (https://api.crossref.org)
local M = {}

local log = require("refman.log")

local CROSSREF_API = "https://api.crossref.org/works"

---Normalize a DOI by stripping URL prefixes and trailing punctuation.
---@param doi string
---@return string
local function clean_doi(doi)
  return (doi:gsub("^https?://doi%.org/", "")
    :gsub("^doi:", "")
    :gsub("^DOI:", "")
    :gsub("[.,;:)%]%[\"?!']+$", "")
    :gsub("^%s+", "")
    :gsub("%s+$", ""))
end

---Map Crossref publication type to a simplified pub_type string.
---@param crossref_type string
---@return string
local function map_type(crossref_type)
  local t = crossref_type:lower()
  if t:match("journal%-article") then return "article" end
  if t:match("book%-chapter") then return "chapter" end
  if t:match("book") then
    if t:match("edited") then return "edited-book" end
    if t:match("monograph") then return "book" end
    return "book"
  end
  if t:match("proceedings") then return "paper-conference" end
  if t:match("dissertation") then return "thesis" end
  if t:match("report") then return "report" end
  if t:match("dataset") then return "dataset" end
  if t:match("standard") then return "standard" end
  return crossref_type
end

---Extract the four-digit year from Crossref date-parts.
---@param date_parts table?
---@return string|nil
local function extract_year(date_parts)
  if not date_parts or not date_parts["date-parts"] then
    return nil
  end
  for _, parts in ipairs(date_parts["date-parts"]) do
    if parts[1] and tonumber(parts[1]) then
      return tostring(parts[1])
    end
  end
  return nil
end

---Build an author string from Crossref author data.
---@param authors table[]
---@return string|nil
local function build_author_string(authors)
  if not authors or #authors == 0 then
    return nil
  end
  local names = {}
  for _, a in ipairs(authors) do
    local family = a.family or ""
    local given = a.given or ""
    if family ~= "" then
      table.insert(names, family .. (given ~= "" and ", " .. given or ""))
    elseif a.name then
      table.insert(names, a.name)
    end
  end
  return #names > 0 and table.concat(names, "; ") or nil
end

---Fetch metadata from Crossref for a given DOI.
---Returns a RefmanEntry with all available fields, or nil on failure.
---@param doi string
---@return RefmanEntry?
function M.fetch(doi)
  doi = clean_doi(doi)
  if doi == "" then
    log.warn("Crossref: empty DOI after cleaning")
    return nil
  end

  local db = require("refman.db")
  local raw = db.exec_cmd('curl -s -L "' .. CROSSREF_API .. "/" .. doi .. '"')
  if not raw or raw == "" then
    log.warn("Crossref: no response for DOI " .. doi)
    return nil
  end

  local ok, data = pcall(vim.json.decode, raw)
  if not ok or not data or not data.message then
    log.warn("Crossref: JSON parse failed for DOI " .. doi)
    return nil
  end

  local msg = data.message
  local entry = {}

  entry.doi = msg.DOI
  entry.pub_type = map_type(msg.type)
  entry.source = "crossref"

  -- title
  if msg.title and #msg.title > 0 then
    entry.title = msg.title[1]
  end

  -- authors
  entry.author = build_author_string(msg.author)

  -- abstract
  if msg.abstract and msg.abstract ~= "" then
    local ab = msg.abstract:gsub("<jats:title>[^<]*</jats:title>", "")
      :gsub("<jats:p>", "")
      :gsub("</jats:p>", "")
      :gsub("</?[^>]+>", "")
      :gsub("&lt;", "<")
      :gsub("&gt;", ">")
      :gsub("&amp;", "&")
      :gsub("%s+", " ")
    entry.abstract = ab:match("^%s*(.-)%s*$")
  end

  -- keywords / subjects
  if msg.subject and #msg.subject > 0 then
    entry.keywords = msg.subject
  end

  -- journal / container
  if msg["container-title"] and #msg["container-title"] > 0 then
    entry.journal = msg["container-title"][1]
  end

  -- volume, issue, pages
  entry.volume = msg.volume
  entry.issue = msg.issue
  entry.pages = msg.page

  -- year
  -- priority: published-print > published-online > created > issued
  entry.year = extract_year(msg["published-print"])
    or extract_year(msg["published-online"])
    or extract_year(msg["created"])
    or extract_year(msg.issued)

  -- publisher
  entry.publisher = msg.publisher

  -- ISSN
  if msg["issn-type"] then
    for _, issn in ipairs(msg["issn-type"]) do
      if issn.type == "print" then
        entry.issn = issn.value
        break
      end
    end
    if not entry.issn then
      entry.issn = msg["issn-type"][1].value
    end
  elseif msg.ISSN and #msg.ISSN > 0 then
    entry.issn = msg.ISSN[1]
  end

  -- ISBN
  if msg["isbn-type"] and #msg["isbn-type"] > 0 then
    entry.isbn = msg["isbn-type"][1].value
  elseif msg.ISBN and #msg.ISBN > 0 then
    entry.isbn = msg.ISBN[1]
  end

  -- isbn_doi composite (backwards compat)
  if entry.doi then
    entry.isbn_doi = entry.doi
  elseif entry.isbn then
    entry.isbn_doi = entry.isbn
  end

  -- fulltext URL
  if msg.link then
    for _, link in ipairs(msg.link) do
      local ct = link["content-type"] or ""
      if ct == "text/html" or ct == "application/pdf" then
        entry.url = link.URL
        break
      end
    end
    if not entry.url and #msg.link > 0 then
      entry.url = msg.link[1].URL
    end
  end

  log.debug("Crossref: fetched metadata for DOI " .. doi)
  return entry
end

---Check if Crossref API is reachable.
---@return boolean
function M.probe()
  local db = require("refman.db")
  local raw = db.exec_cmd('curl -s -o /dev/null -w "%{http_code}" "https://api.crossref.org"')
  return raw == "200"
end

return M
