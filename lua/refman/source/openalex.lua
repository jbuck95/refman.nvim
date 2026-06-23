---@tag refman.source.openalex
---Fetches metadata from the OpenAlex REST API (https://api.openalex.org)
---OpenAlex aggregates Crossref, PubMed, arXiv, ORCID and many other sources.
local M = {}

local log = require("refman.log")

local OPENALEX_API = "https://api.openalex.org"

---Reconstruct a human-readable abstract from OpenAlex's inverted index format.
---@param inverted_index table<string, integer[]>
---@return string|nil
local function rebuild_abstract(inverted_index)
  if not inverted_index or type(inverted_index) ~= "table" then
    return nil
  end
  local word_positions = {}
  for word, positions in pairs(inverted_index) do
    for _, pos in ipairs(positions) do
      word_positions[pos] = word
    end
  end
  local words = {}
  for i = 1, #word_positions do
    if word_positions[i] then
      words[i] = word_positions[i]
    end
  end
  return #words > 0 and table.concat(words, " ") or nil
end

---Map OpenAlex type to simplified pub_type.
---@param oa_type string
---@return string
local function map_type(oa_type)
  local t = oa_type:lower()
  if t == "journal-article" then return "article" end
  if t == "book" then return "book" end
  if t == "book-chapter" then return "chapter" end
  if t == "proceedings-article" then return "paper-conference" end
  if t == "dissertation" then return "thesis" end
  if t == "report" then return "report" end
  if t == "dataset" then return "dataset" end
  if t == "standard" then return "standard" end
  if t == "preprint" then return "paper" end
  if t == "other" then return "other" end
  return oa_type
end

---Build author string from OpenAlex authorships.
---@param authorships table[]
---@return string|nil
local function build_author_string(authorships)
  if not authorships or #authorships == 0 then
    return nil
  end
  local names = {}
  for _, a in ipairs(authorships) do
    if a.author and a.author.display_name then
      table.insert(names, a.author.display_name)
    end
  end
  return #names > 0 and table.concat(names, "; ") or nil
end

---Fetch metadata from OpenAlex by DOI.
---@param doi string
---@return RefmanEntry?
function M.fetch_by_doi(doi)
  doi = doi:gsub("^https?://doi%.org/", "")
    :gsub("^doi:", "")
    :gsub("^DOI:", "")
    :gsub("[.,;:)%]%[\"?!']+$", "")
    :gsub("^%s+", "")
    :gsub("%s+$", "")
  if doi == "" then
    return nil
  end

  local db = require("refman.db")
  local url = OPENALEX_API .. "/works/doi:" .. doi
  local raw = db.exec_cmd('curl -s -L --max-time 10 "' .. url .. '"')
  if not raw or raw == "" then
    log.warn("OpenAlex: no response for DOI " .. doi)
    return nil
  end

  local ok, data = pcall(vim.json.decode, raw)
  if not ok or not data or data.error then
    log.warn("OpenAlex: invalid response for DOI " .. doi)
    return nil
  end

  return M._parse_work(data)
end

---Search OpenAlex by title.
---@param title string
---@return RefmanEntry?
function M.search_by_title(title)
  local db = require("refman.db")
  local encoded = title
    :gsub("([^%w%-%.%_%~ ])", function(c)
      return string.format("%%%02X", string.byte(c))
    end)
    :gsub(" ", "+")
  local url = OPENALEX_API .. "/works?search=" .. encoded .. "&per_page=1"
  local raw = db.exec_cmd('curl -s -L --max-time 10 "' .. url .. '"')

  if not raw or raw == "" then return nil end

  local ok, data = pcall(vim.json.decode, raw)
  if not ok or not data or not data.results or #data.results == 0 then
    return nil
  end

  return M._parse_work(data.results[1])
end

---Parse an OpenAlex work object into a RefmanEntry.
---@param work table
---@return RefmanEntry
function M._parse_work(work)
  local entry = {}

  entry.doi = work.doi:gsub("^https?://doi%.org/", "")
  entry.source = "openalex"
  entry.title = work.title
  entry.pub_type = map_type(work.type or "other")
  entry.author = build_author_string(work.authorships)
  entry.abstract = rebuild_abstract(work.abstract_inverted_index)

  -- keywords (concepts)
  if work.concepts and #work.concepts > 0 then
    entry.keywords = {}
    for _, c in ipairs(work.concepts) do
      if c.display_name and c.level ~= nil and c.level <= 1 then
        table.insert(entry.keywords, c.display_name)
      end
    end
    if #entry.keywords == 0 then
      entry.keywords = nil
    end
  end

  -- journal / container
  if work.primary_location and work.primary_location.source then
    local src = work.primary_location.source
    if src.display_name then
      entry.journal = src.display_name
    end
    if src.issn_l then
      entry.issn = src.issn_l
    end
  end

  -- biblio fields
  if work.biblio then
    entry.volume = work.biblio.volume
    entry.issue = work.biblio.issue
    if work.biblio.first_page and work.biblio.last_page then
      entry.pages = work.biblio.first_page .. "-" .. work.biblio.last_page
    elseif work.biblio.first_page then
      entry.pages = work.biblio.first_page
    end
  end

  -- year
  if work.publication_date then
    entry.year = work.publication_date:match("^(%d%d%d%d)")
  end

  -- fulltext URL
  if work.open_access and work.open_access.oa_url then
    entry.url = work.open_access.oa_url
  elseif work.primary_location and work.primary_location.landing_page_url then
    entry.url = work.primary_location.landing_page_url
  end

  -- isbn_doi composite
  entry.isbn_doi = entry.doi

  -- PMID if available
  if work.ids and work.ids.pmid then
    entry.pmid = tostring(work.ids.pmid)
  end

  return entry
end

M.fetch = M.fetch_by_doi

---Check if OpenAlex API is reachable.
---@return boolean
function M.probe()
  local db = require("refman.db")
  local raw = db.exec_cmd('curl -s -o /dev/null -w "%{http_code}" "https://api.openalex.org/works/doi:10.1038/nature12373"')
  return raw == "200"
end

return M
