---@tag refman.db.sqlite
---SQLite backend for refman bibliography database.
---Uses sqlite3 CLI via vim.fn.system.
local M = {}

local log = require("refman.log")
local config

-- Keep in sync with CREATE TABLE columns in M.init()
M.VALID_COLUMNS = {
  author     = true,
  title      = true,
  citation   = true,
  isbn_doi   = true,
  tags       = true,
  notes      = true,
  abstract   = true,
  keywords   = true,
  pub_type   = true,
  journal    = true,
  volume     = true,
  issue      = true,
  pages      = true,
  year       = true,
  publisher  = true,
  doi        = true,
  isbn       = true,
  issn       = true,
  url        = true,
  pmid       = true,
  source     = true,
}

function M.set_config(cfg)
  config = cfg or vim.tbl_extend("keep", {}, require("refman.config.defaults"))
end

---Resolve the SQLite database path (replace .md extension with .sqlite3).
---@return string
local function db_path()
  return (config.db_file or vim.fn.expand("~/Documents/bibliography.md")):gsub("%.md$", ".sqlite3")
end

---Execute a single SQL command and return stdout.
---@param sql string
---@return string
local function sqlite(sql)
  local path = db_path()
  local cmd = string.format('sqlite3 -json -bail "%s" %s', path, vim.fn.shellescape(sql))
  local result = vim.fn.system(cmd)
  if vim.v.shell_error ~= 0 then
    log.warn(string.format("sqlite3 error: %s", vim.v.shell_error))
  end
  return result:gsub("^%s+", ""):gsub("%s+$", "")
end

---Check if sqlite3 CLI is available.
---@return boolean
function M.is_available()
  local result = vim.fn.system("which sqlite3 2>/dev/null"):gsub("%s+$", "")
  return result ~= ""
end

---Initialize the database schema.
---@return boolean
function M.init(db_path_override)
  if not config then
    config = vim.tbl_extend("keep", {}, require("refman.config.defaults"))
  end
  if db_path_override then
    config.db_file = db_path_override
  end

  if not M.is_available() then
    vim.notify("[refman] sqlite3 CLI not found", vim.log.levels.ERROR)
    return false
  end

  local path = db_path()
  log.info("Initializing SQLite database: " .. path)

  sqlite([[
CREATE TABLE IF NOT EXISTS entries (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    author      TEXT    NOT NULL,
    title       TEXT    NOT NULL,
    citation    TEXT,
    isbn_doi    TEXT,
    tags        TEXT,
    notes       TEXT,
    abstract    TEXT,
    keywords    TEXT,
    pub_type    TEXT,
    journal     TEXT,
    volume      TEXT,
    issue       TEXT,
    pages       TEXT,
    year        TEXT,
    publisher   TEXT,
    doi         TEXT UNIQUE,
    isbn        TEXT,
    issn        TEXT,
    url         TEXT,
    pmid        TEXT,
    source      TEXT,
    added_at    TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at  TEXT
);

CREATE INDEX IF NOT EXISTS idx_entries_author ON entries(author);
CREATE INDEX IF NOT EXISTS idx_entries_title  ON entries(title);
CREATE INDEX IF NOT EXISTS idx_entries_doi    ON entries(doi);
CREATE INDEX IF NOT EXISTS idx_entries_year   ON entries(year);

CREATE VIRTUAL TABLE IF NOT EXISTS entries_fts USING fts5(
    author, title, citation, abstract, keywords, journal, notes, tags,
    content=entries, content_rowid=id
);

CREATE TRIGGER IF NOT EXISTS entries_ai AFTER INSERT ON entries BEGIN
    INSERT INTO entries_fts(rowid, author, title, citation, abstract, keywords, journal, notes, tags)
    VALUES (new.id, new.author, new.title, new.citation, new.abstract, new.keywords, new.journal, new.notes, new.tags);
END;

CREATE TRIGGER IF NOT EXISTS entries_ad AFTER DELETE ON entries BEGIN
    INSERT INTO entries_fts(entries_fts, rowid, author, title, citation, abstract, keywords, journal, notes, tags)
    VALUES ('delete', old.id, old.author, old.title, old.citation, old.abstract, old.keywords, old.journal, old.notes, old.tags);
END;

CREATE TRIGGER IF NOT EXISTS entries_au AFTER UPDATE ON entries BEGIN
    INSERT INTO entries_fts(entries_fts, rowid, author, title, citation, abstract, keywords, journal, notes, tags)
    VALUES ('delete', old.id, old.author, old.title, old.citation, old.abstract, old.keywords, old.journal, old.notes, old.tags);
    INSERT INTO entries_fts(rowid, author, title, citation, abstract, keywords, journal, notes, tags)
    VALUES (new.id, new.author, new.title, new.citation, new.abstract, new.keywords, new.journal, new.notes, new.tags);
END;
]])

  return true
end

---Parse a JSON array of entry objects from sqlite3 output.
---@param json_str string
---@return RefmanEntry[]
local function parse_entries_json(json_str)
  if not json_str or json_str == "" then
    return {}
  end
  local ok, data = pcall(vim.json.decode, json_str)
  if not ok or not data then
    return {}
  end
  local entries = {}
  for _, row in ipairs(data) do
    for k, v in pairs(row) do
      if v == vim.NIL then row[k] = nil end
    end
    if row.keywords and row.keywords ~= "" then
      local okw, keywords = pcall(vim.json.decode, row.keywords)
      row.keywords = okw and keywords or nil
    end
    entries[#entries + 1] = row
  end
  return entries
end

---Escape a string for safe SQL injection (sqlite3 shell).
---@param s string
---@return string
local function esc(s)
  if not s then return "NULL" end
  return "'" .. s:gsub("'", "''") .. "'"
end

---Insert or update a 'keywords' JSON array value.
---@param keywords string[]?
---@return string SQL-compatible NULL or JSON string
local function json_keywords(keywords)
  if not keywords or #keywords == 0 then
    return "NULL"
  end
  return esc(vim.json.encode(keywords))
end

-- ── CRUD API ────────────────────────────────────────────────────────────────

---@return RefmanEntry[]
function M.read_all()
  local json = sqlite("SELECT * FROM entries ORDER BY author, title;")
  return parse_entries_json(json)
end

---@param id integer
---@return RefmanEntry?
function M.get_entry(id)
  local json = sqlite("SELECT * FROM entries WHERE id = " .. tostring(id) .. ";")
  local entries = parse_entries_json(json)
  return entries[1]
end

---@param entry RefmanEntry
---@return integer|false  entry id on success, false if duplicate
function M.add_entry(entry)
  local doi = entry.doi or (entry.pmid and "pmid:" .. entry.pmid)
  local isbn_doi = doi or entry.isbn

  if doi then
    local existing = sqlite("SELECT id FROM entries WHERE doi = " .. esc(doi) .. ";")
    local parsed = parse_entries_json(existing)
    if #parsed > 0 then
      vim.notify("Entry already exists (DOI: " .. doi .. ")", vim.log.levels.WARN)
      return false
    end
  end

  if entry.author and entry.title then
    local dup_check = sqlite(
      "SELECT id FROM entries WHERE author = " .. esc(entry.author) .. " AND title = " .. esc(entry.title) .. ";"
    )
    local dup = parse_entries_json(dup_check)
    if #dup > 0 then
      vim.notify("Entry already exists: " .. entry.title, vim.log.levels.WARN)
      return false
    end
  end

  local sql = string.format(
    "INSERT INTO entries (author, title, citation, isbn_doi, tags, notes, abstract, keywords, pub_type, journal, volume, issue, pages, year, publisher, doi, isbn, issn, url, pmid, source) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s);",
    esc(entry.author),
    esc(entry.title),
    esc(entry.citation),
    esc(isbn_doi),
    esc(entry.tags),
    esc(entry.notes),
    esc(entry.abstract),
    json_keywords(entry.keywords),
    esc(entry.pub_type),
    esc(entry.journal),
    esc(entry.volume),
    esc(entry.issue),
    esc(entry.pages),
    esc(entry.year),
    esc(entry.publisher),
    esc(entry.doi),
    esc(entry.isbn),
    esc(entry.issn),
    esc(entry.url),
    esc(entry.pmid),
    esc(entry.source)
  )

  sqlite(sql)
  if vim.v.shell_error ~= 0 then
    return false
  end

  return true
end

---@param id integer
---@param updates table Field → value map
---@return boolean ok
---@return string? error_message
function M.update_entry(id, updates)
  local unknown = {}
  for field, _ in pairs(updates) do
    if not M.VALID_COLUMNS[field] then
      unknown[#unknown + 1] = field
    end
  end
  if #unknown > 0 then
    local msg = "Unknown field(s): " .. table.concat(unknown, ", ")
    log.warn("update_entry: " .. msg .. " for id " .. tostring(id))
    return false, msg
  end

  if updates.doi and updates.doi ~= "" then
    local check = sqlite("SELECT id FROM entries WHERE doi = " .. esc(updates.doi) .. ";")
    local rows = parse_entries_json(check)
    for _, row in ipairs(rows) do
      if row.id ~= id then
        return false, "DOI already used by entry #" .. tostring(row.id) .. ": " .. updates.doi
      end
    end
  end

  local sets = {}
  for field, value in pairs(updates) do
    if field == "keywords" then
      table.insert(sets, "keywords = " .. json_keywords(value))
    else
      table.insert(sets, field .. " = " .. esc(value))
    end
  end
  if #sets == 0 then
    return false, "No fields to update"
  end
  table.insert(sets, "updated_at = datetime('now')")
  local update_sql = "UPDATE entries SET " .. table.concat(sets, ", ") .. " WHERE id = " .. tostring(id) .. ";"
  local stderr_file = os.tmpname()
  local cmd = string.format('sqlite3 -json -bail "%s" 2>%s %s', db_path(), stderr_file, vim.fn.shellescape(update_sql))
  vim.fn.system(cmd)
  if vim.v.shell_error ~= 0 then
    local stderr_text = ""
    local f = io.open(stderr_file)
    if f then
      stderr_text = f:read("*a"):gsub("^%s+", ""):gsub("%s+$", "")
      f:close()
    end
    os.remove(stderr_file)
    local msg = stderr_text ~= "" and stderr_text or ("sqlite3 error (exit " .. vim.v.shell_error .. ")")
    log.warn("update_entry failed for id " .. tostring(id) .. ": " .. msg)
    return false, msg
  end
  os.remove(stderr_file)
  return true
end

---@param id integer
---@return boolean
function M.delete_entry(id)
  sqlite("DELETE FROM entries WHERE id = " .. tostring(id) .. ";")
  return vim.v.shell_error == 0
end

-- ── search API ──────────────────────────────────────────────────────────────

---Full-text search via FTS5.
---@param query string
---@return RefmanEntry[]
function M.search_fulltext(query)
  local escaped = query:gsub("'", "''")
  local sql = string.format(
    "SELECT e.* FROM entries e JOIN entries_fts f ON e.id = f.rowid WHERE entries_fts MATCH '%s' ORDER BY rank;",
    escaped
  )
  return parse_entries_json(sqlite(sql))
end

---Search by author (LIKE).
---@param author string
---@return RefmanEntry[]
function M.search_by_author(author)
  return parse_entries_json(sqlite("SELECT * FROM entries WHERE author LIKE " .. esc("%" .. author .. "%") .. " ORDER BY year DESC;"))
end

---Search by tag (exact or partial).
---@param tag string
---@return RefmanEntry[]
function M.search_by_tag(tag)
  local json = sqlite("SELECT * FROM entries WHERE tags LIKE " .. esc("%" .. tag .. "%") .. " ORDER BY author;")
  return parse_entries_json(json)
end

---Search by DOI.
---@param doi string
---@return RefmanEntry?
function M.search_by_doi(doi)
  local entries = parse_entries_json(sqlite("SELECT * FROM entries WHERE doi = " .. esc(doi) .. ";"))
  return entries[1]
end

-- ── migration ───────────────────────────────────────────────────────────────

---Import entries from a list.
---@param entries RefmanEntry[]
---@return integer Number of entries imported
function M.import_entries(entries)
  local count = 0
  for _, entry in ipairs(entries) do
    local result = M.add_entry(entry)
    if result then
      count = count + 1
    end
  end
  return count
end

function M.search_entries(query)
  return M.search_fulltext(query)
end

---Open the bibliography browser (Telescope-based).
function M.open_database()
  require("refman.telescope.browser").open()
end

return M
