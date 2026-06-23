---@tag refman.source.arxiv
---Fetches metadata from the arXiv API (https://export.arxiv.org/api)
local M = {}

local log = require("refman.log")

local ARXIV_API = "https://export.arxiv.org/api/query"

---Strip HTML/XML tags and decode basic entities.
---@param text string
---@return string
local function strip_tags(text)
  return (text:gsub("<[^>]+>", "")
    :gsub("&amp;", "&")
    :gsub("&lt;", "<")
    :gsub("&gt;", ">")
    :gsub("&quot;", "\"")
    :gsub("\n%s+", " ")
    :gsub("%s+", " ")
    :gsub("^%s+", "")
    :gsub("%s+$", ""))
end

---Check if an arXiv ID looks valid (e.g. 2103.12345 or hep-th/9901001).
---@param id string
---@return boolean
local function is_arxiv_id(id)
  return id:match("^%d%d%d%d%.%d%d%d%d%d?$") ~= nil
    or id:match("^[a-z%-]+/%d%d%d%d%d%d%d$") ~= nil
end

---Fetch metadata from arXiv by ID.
---@param arxiv_id string
---@return RefmanEntry?
function M.fetch_by_id(arxiv_id)
  arxiv_id = arxiv_id:gsub("^https?://arxiv%.org/abs/", "")
    :gsub("^arxiv:", "")
    :gsub("[.,;:)%]%[\"?!']+$", "")
    :gsub("^%s+", "")
    :gsub("%s+$", "")

  if not is_arxiv_id(arxiv_id) then
    return nil
  end

  local db = require("refman.db")
  local url = ARXIV_API .. "?id_list=" .. arxiv_id .. "&max_results=1"
  local raw = db.exec_cmd('curl -s -L --max-time 10 "' .. url .. '"')

  if not raw or raw == "" or not raw:match("<entry>") then
    log.warn("arXiv: no entry found for ID " .. arxiv_id)
    return nil
  end

  return M._parse_atom(raw)
end

---Fetch metadata from a DOI (extracts arXiv ID from DOI suffix).
---@param doi string
---@return RefmanEntry?
function M.fetch(doi)
  doi = doi:gsub("^https?://doi%.org/", "")
    :gsub("^doi:", "")
    :gsub("^DOI:", "")
    :gsub("[.,;:)%]%[\"?!']+$", "")
    :gsub("^%s+", "")
    :gsub("%s+$", "")

  if not doi:match("^10%.48550/") then
    return nil
  end

  local arxiv_id = doi:match("/arXiv%.(.+)$") or doi:match("/arxiv%.(.+)$")
  if not arxiv_id then
    return nil
  end

  return M.fetch_by_id(arxiv_id)
end

---Search arXiv by title.
---@param title string
---@return RefmanEntry?
function M.search_by_title(title)
  local db = require("refman.db")
  local encoded = title
    :gsub("([^%w%-%.%_%~ ])", function(c)
      return string.format("%%%02X", string.byte(c))
    end)
    :gsub(" ", "+")
  local url = ARXIV_API .. "?search_query=ti:" .. encoded .. "&max_results=1"
  local raw = db.exec_cmd('curl -s -L --max-time 10 "' .. url .. '"')

  if not raw or raw == "" or not raw:match("<entry>") then
    return nil
  end

  return M._parse_atom(raw)
end

---Parse arXiv Atom XML response into a RefmanEntry.
---@param xml string
---@return RefmanEntry
function M._parse_atom(xml)
  -- Extract the first <entry> block
  local entry_xml = xml:match("<entry>(.-)</entry>")
  if not entry_xml then
    return nil
  end

  local entry = {}
  entry.source = "arxiv"
  entry.pub_type = "paper"

  -- title
  local raw_title = entry_xml:match("<title>(.-)</title>")
  if raw_title then
    entry.title = strip_tags(raw_title)
  end

  -- summary / abstract
  local raw_summary = entry_xml:match("<summary>(.-)</summary>")
  if raw_summary then
    entry.abstract = strip_tags(raw_summary)
  end

  -- DOI
  entry.doi = entry_xml:match("<arxiv:doi>(.-)</arxiv:doi>")
    or entry_xml:match("<doi>(.-)</doi>")

  -- published (year)
  local published = entry_xml:match("<published>(.-)</published>")
  if published then
    entry.year = published:match("^(%d%d%d%d)")
  end

  -- authors
  local authors = {}
  for name in entry_xml:gmatch("<name>(.-)</name>") do
    table.insert(authors, strip_tags(name))
  end
  if #authors > 0 then
    entry.author = table.concat(authors, "; ")
  end

  -- categories as keywords
  local keywords = {}
  for cat in entry_xml:gmatch([[category term="([^"]+)]]) do
    table.insert(keywords, cat)
  end
  if #keywords > 0 then
    entry.keywords = keywords
  end

  -- journal reference (for published versions)
  local journal_ref = entry_xml:match("<arxiv:journal_ref>(.-)</arxiv:journal_ref>")
  if journal_ref then
    entry.journal = strip_tags(journal_ref)
  end

  -- URL
  local arxiv_id = entry_xml:match("<id>(.-)</id>"):gsub("^https?://arxiv%.org/abs/", "")
  if arxiv_id then
    entry.url = "https://arxiv.org/abs/" .. arxiv_id
  end

  -- isbn_doi composite
  if entry.doi then
    entry.isbn_doi = entry.doi
  else
    entry.isbn_doi = arxiv_id
  end

  return entry
end

---Check if arXiv API is reachable.
---@return boolean
function M.probe()
  local db = require("refman.db")
  local raw = db.exec_cmd('curl -s -o /dev/null -w "%{http_code}" "https://export.arxiv.org/api/query?search_query=all:test&max_results=1"')
  return raw == "200"
end

return M
