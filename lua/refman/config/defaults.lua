---@class RefmanConfig
---@field log_level    string
---@field db_file      string
---@field db_backend   string             "markdown"|"sqlite"
---@field source_apis  RefmanSourceConfig
---@field csl          RefmanCSLConfig

---@class RefmanSourceConfig
---@field crossref  {enabled:boolean}
---@field openalex  {enabled:boolean}
---@field arxiv     {enabled:boolean}
---@field pubmed    {enabled:boolean, api_key?:string}

---@class RefmanCSLConfig
---@field enabled        boolean
---@field default_style  string            key of default style from csl.styles
---@field cite_mode      string            "full"|"inline"|"both"
---@field inline_format  string            Template for inline citations, e.g. "{author} ({year})"
---@field styles         RefmanCSLStyle[]

---@class RefmanCSLStyle
---@field name string
---@field key  string
---@field path string
---@field lang string

---@class RefmanEntry
---@field author       string
---@field title        string
---@field citation     string?
---@field isbn_doi     string
---@field tags         string?
---@field notes        string?
---@field abstract     string?
---@field keywords     string[]?
---@field pub_type     string?
---@field journal      string?
---@field volume       string?
---@field issue        string?
---@field pages        string?
---@field year         string?
---@field publisher    string?
---@field doi          string?
---@field isbn         string?
---@field issn         string?
---@field url          string?
---@field source       string?
---@field added_at     string?
---@field updated_at   string?

local plugin_root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h")

return {
  log_level = "verbose",
  db_file = vim.fn.expand("~/Documents/bibliography.md"),
  db_backend = "sqlite",

  source_apis = {
    crossref = { enabled = true },
    openalex = { enabled = false },
    arxiv    = { enabled = false },
    pubmed   = { enabled = false },
  },

  csl = {
    enabled = true,
    default_style = "din-1505-2",
    cite_mode = "full",
    inline_format = "{author} ({year})",
    styles = {
      {
        name = "DIN 1505-2 (German)",
        key = "din-1505-2",
        path = plugin_root .. "/csl/din-1505-2.csl",
        lang = "de-DE",
      },
      {
        name = "Chicago (notes-bibliography)",
        key = "chicago",
        path = plugin_root .. "/csl/chicago-note-bibliography.csl",
        lang = "en-US",
      },
      {
        name = "MLA (Modern Language Assoc.)",
        key = "mla",
        path = plugin_root .. "/csl/modern-language-association.csl",
        lang = "en-US",
      },
      {
        name = "APA 7th Edition",
        key = "apa",
        path = plugin_root .. "/csl/apa.csl",
        lang = "en-US",
      },
    },
  },
}
