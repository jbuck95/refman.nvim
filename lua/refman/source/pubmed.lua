---@tag refman.source.pubmed
---Fetches metadata from the PubMed Entrez E-utilities API
---Two-step: ESearch (query → PMIDs) then EFetch (PMID → full metadata)
local M = {}

local log = require("refman.log")

local ESEARCH_URL = "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi"
local EFETCH_URL = "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi"

---@type string|nil
local api_key = nil

---Set the NCBI API key for higher rate limits (10 req/s vs 3 req/s).
---@param key string
function M.set_api_key(key)
  api_key = key
end

---Build an API key query parameter if configured.
---@return string
local function api_key_param()
  if api_key then
    return "&api_key=" .. api_key
  end
  return ""
end

---Strip XML tags and decode entities.
---@param text string
---@return string
local function strip_tags(text)
  if not text then
    return nil
  end
  return (text:gsub("<[^>]+>", "")
    :gsub("&amp;", "&")
    :gsub("&lt;", "<")
    :gsub("&gt;", ">")
    :gsub("%s+", " ")
    :gsub("^%s+", "")
    :gsub("%s+$", ""))
end

---Map PubMed publication type.
---@param pub_types string[]
---@return string
local function map_type(pub_types)
  if not pub_types or #pub_types == 0 then
    return "article"
  end
  for _, t in ipairs(pub_types) do
    local lt = t:lower()
    if lt:match("journal article") then return "article" end
    if lt:match("review") then return "review-article" end
    if lt:match("book") then return "book" end
    if lt:match("clinical trial") then return "article" end
    if lt:match("editorial") then return "article" end
    if lt:match("letter") then return "article" end
  end
  return "article"
end

---Fetch metadata by DOI via PubMed.
---@param doi string
---@return RefmanEntry?
function M.fetch_by_doi(doi)
  doi = doi:gsub("^https?://doi%.org/", "")
    :gsub("^doi:", "")
    :gsub("^DOI:", "")
    :gsub("[.,;:)%]%[\"?!']+$", "")
    :gsub("^%s+", "")
    :gsub("%s+$", "")

  local db = require("refman.db")
  local esearch_url = ESEARCH_URL
    .. "?db=pubmed&retmode=json&term="
    .. doi
    .. "%5Bdoi%5D&retmax=1"
    .. api_key_param()

  local raw = db.exec_cmd('curl -s -L --max-time 10 "' .. esearch_url .. '"')
  if not raw or raw == "" then
    log.warn("PubMed ESearch: no response for DOI " .. doi)
    return nil
  end

  local ok, data = pcall(vim.json.decode, raw)
  if not ok or not data or not data.esearchresult then
    return nil
  end

  local idlist = data.esearchresult.idlist
  if not idlist or #idlist == 0 then
    return nil
  end

  return M.fetch_by_pmid(idlist[1])
end

M.fetch = M.fetch_by_doi

---Fetch metadata by PubMed ID.
---@param pmid string|integer
---@return RefmanEntry?
function M.fetch_by_pmid(pmid)
  local db = require("refman.db")
  local efetch_url = EFETCH_URL
    .. "?db=pubmed&id="
    .. tostring(pmid)
    .. "&retmode=xml"
    .. api_key_param()

  local raw = db.exec_cmd('curl -s -L --max-time 10 "' .. efetch_url .. '"')
  if not raw or raw == "" or not raw:match("<PubmedArticle>") then
    log.warn("PubMed EFetch: no article data for PMID " .. tostring(pmid))
    return nil
  end

  return M._parse_pubmed_xml(raw)
end

---Parse PubMed EFetch XML into a RefmanEntry.
---@param xml string
---@return RefmanEntry
function M._parse_pubmed_xml(xml)
  local entry = {}
  entry.source = "pubmed"

  -- PMID
  entry.pmid = xml:match("<PMID.->(%d+)</PMID>")

  -- title
  local raw_title = xml:match("<ArticleTitle>(.-)</ArticleTitle>")
  if raw_title then
    entry.title = strip_tags(raw_title)
  end

  -- abstract: collect all AbstractText parts
  local abstracts = {}
  for tag, text in xml:gmatch([[<AbstractText([^>]*)>(.-)</AbstractText>]]) do
    local label = tag:match([[Label="([^"]+)]]) or tag:match("Label='([^']+)'")
    if label and text and text ~= "" then
      table.insert(abstracts, label .. ": " .. text)
    elseif text and text ~= "" then
      table.insert(abstracts, text)
    end
  end
  if #abstracts > 0 then
    entry.abstract = strip_tags(table.concat(abstracts, " "))
  end

  -- publication type
  local pub_types = {}
  for pt in xml:gmatch("<PublicationType[^>]*>(.-)</PublicationType>") do
    table.insert(pub_types, strip_tags(pt))
  end
  entry.pub_type = map_type(pub_types)

  -- authors
  local authors = {}
  for author_block in xml:gmatch("<Author.->(.-)</Author>") do
    local last = author_block:match("<LastName>(.-)</LastName>")
    local first = author_block:match("<ForeName>(.-)</ForeName>")
    if last then
      table.insert(authors, last .. (first and ", " .. first or ""))
    end
  end
  if #authors == 0 then
    local collective = xml:match("<CollectiveName>(.-)</CollectiveName>")
    if collective then
      authors = { strip_tags(collective) }
    end
  end
  if #authors > 0 then
    entry.author = table.concat(authors, "; ")
  end

  -- year
  local pub_date = xml:match("<PubDate>(.-)</PubDate>")
  if pub_date then
    entry.year = pub_date:match("<Year>(.-)</Year>")
  end

  -- journal
  local journal = xml:match("<Title>(.-)</Title>")
  if journal then
    entry.journal = strip_tags(journal)
  end

  -- volume, issue, pages
  entry.volume = xml:match("<Volume>(.-)</Volume>")
  entry.issue = xml:match("<Issue>(.-)</Issue>")
  local pages = xml:match("<MedlinePgn>(.-)</MedlinePgn>")
  if pages then
    entry.pages = strip_tags(pages)
  end

  -- DOI
  entry.doi = xml:match([[<ArticleId IdType="doi">(.-)</ArticleId>]])
    or xml:match([[<ArticleId IdType="doi"%s->(.-)</ArticleId>]])

  -- ISSN
  entry.issn = xml:match("<ISSN[^>]*>(.-)</ISSN>")

  if entry.doi then
    entry.isbn_doi = entry.doi
  elseif entry.pmid then
    entry.isbn_doi = "pmid:" .. entry.pmid
  end

  -- MeSH terms as keywords
  local keywords = {}
  for mesh in xml:gmatch("<DescriptorName[^>]*>(.-)</DescriptorName>") do
    table.insert(keywords, strip_tags(mesh))
  end
  if #keywords > 0 then
    entry.keywords = keywords
  end

  return entry
end

---Check if PubMed API is reachable.
---@return boolean
function M.probe()
  local db = require("refman.db")
  local raw = db.exec_cmd('curl -s -o /dev/null -w "%{http_code}" "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi?db=pubmed&retmode=json&term=test&retmax=1"')
  return raw == "200"
end

return M
