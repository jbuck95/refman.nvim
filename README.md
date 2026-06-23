# refman.nvim


Fetch Citations from DOI/ISBN and manage references.

DOI/ISBN → Source APIs (crossref, openalex, OpenLibrary) → CSL via citation-js → formatted citation in buffer.

![refman.nvim demo](https://github.com/user-attachments/assets/902be61e-a113-4945-b520-a9060c7b373b)

## Requirements

### System
- `curl` -- for API calls
- `sqlite3` (CLI) -- for SQLite backend
- Node.js + npm -- for CSL formatting

### citation-js

```bash
npm install -g @citation-js/core @citation-js/plugin-csl
```

### Neovim
- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim)

Verify: `:checkhealth refman`

## Install

### lazy.nvim (minimal)

```lua
{
    "jbuck95/refman.nvim",
    dependencies = {
        "nvim-telescope/telescope.nvim",
    },
    cmd = { "DOI", "ISBN", "RefCite", "RefBrowse", "RefSearch", "RefImport" },
    keys = {
        { "<leader>rs", "<Plug>(RefmanImport)", desc = "Save line as citation" },
        { "<leader>rb", "<Plug>(RefmanBrowse)", desc = "Browse bibliography" },
        { "<leader>ri", "<Plug>(RefmanExport)", desc = "Insert citation" },
        { "<leader>rc", "<Plug>(RefmanCite)",  desc = "Insert inline citation" },
    },
}
```

### lazy.nvim (with custom config)

```lua
{
    "jbuck95/refman.nvim",
    dependencies = {
        "nvim-telescope/telescope.nvim",
    },
    cmd = { "DOI", "ISBN", "RefCite", "RefBrowse", "RefSearch", "RefImport" },
    keys = {
        { "<leader>rs", "<Plug>(RefmanImport)", desc = "Save line as citation" },
        { "<leader>rb", "<Plug>(RefmanBrowse)", desc = "Browse bibliography" },
        { "<leader>ri", "<Plug>(RefmanExport)", desc = "Insert citation" },
        { "<leader>rc", "<Plug>(RefmanCite)",  desc = "Insert inline citation" },
    },
    config = function()
        require("refman").setup({
            log_level = "error",
            db_file = "~/my-bibliography.md",
            csl = {
                default_style = "din-1505-2",
            },
        })
    end,
}
```

## Usage

Bind  ``RefBrowse`` and use the TUI. 

| Command | Action |
|---------|--------|
| `:DOI` (visual selection) | Fetch DOI → pick CSL style → insert citation |
| `:ISBN` (visual selection) | Fetch ISBN → pick CSL style → insert citation |
| `:RefCite` (visual selection) | Fetch DOI/ISBN → insert inline citation `(Author, Year)` |
| `:RefBrowse [query]` | Browse all entries (Telescope) |
| `:RefSearch query` | Full-text search |
| `:RefImport` | Save current line as bibliography entry |
| `:RefOpen` | Open bibliography database |
| `:RefExport` | Browse & insert single citation (Telescope) |
| `:RefMulti` | Browse & insert multiple citations (Telescope) |
| `:RefLog` | Open debug log |
| `:RefCacheClear` | Clear citation cache |

### Telescope browser (RefBrowse / RefExport / RefMulti)

| Key | Action | Config |
|-----|--------|--------|
| `<CR>` | Insert citation(s) | _(fixed)_ |
| `<C-g>` | View entry details | `keys.telescope.detail` |
| `<C-b>` | Insert as formatted bibliography | `keys.telescope.bibliography` |
| `<C-d>` | Delete entry | `keys.telescope.delete` |
| `<Tab>` | Toggle multi-select | `keys.telescope.toggle_multi` |

### Keymaps via `<Plug>` mappings

```lua
vim.keymap.set("n", "<leader>rs", "<Plug>(RefmanImport)", { desc = "Save line as citation" })
vim.keymap.set("n", "<leader>rb", "<Plug>(RefmanBrowse)", { desc = "Browse bibliography" })
vim.keymap.set("n", "<leader>ri", "<Plug>(RefmanExport)", { desc = "Insert citation" })
vim.keymap.set("n", "<leader>rc", "<Plug>(RefmanCite)",  { desc = "Insert inline citation" })
vim.keymap.set("n", "<leader>rm", "<Plug>(RefmanMulti)",  { desc = "Insert multiple citations" })
vim.keymap.set("n", "<leader>rs", "<Plug>(RefmanSearch)", { desc = "Search bibliography" })
```

### Lua API

```lua
local refman = require("refman")
refman.convert_doi_citation()
refman.convert_isbn_citation()
refman.cite_inline_citation()                 -- inline (Author, Year)
refman.import_current_line()
refman.open_database()
refman.export_citation()
refman.export_citations_multi()
refman.search_entries()
refman.clear_cache()
refman.open_log()
refman.setup({ db_file = "~/my-bib.md" })
```

## How it works

```
:DOI / :ISBN
  │
  ▼
Source APIs (opt-in via source_apis)
  ├── crossref  — DOI metadata (title, author, journal, year, ...)
  ├── openalex  — DOI metadata (additional source)
  └── OpenLibrary — ISBN metadata (direct curl, no Python)
  │
  ▼
CSL formatting (citation-js via Node)
  ├── reads CSL-JSON from source data
  ├── formats with .csl style file (din-1505-2, apa, chicago, mla)
  └── output: formatted citation string or inline (Author, Year)
  │
  ▼
Buffer — citation inserted at cursor
Database (SQLite) — entry saved with metadata
```

## Configuration

| Option | Default | Description |
|--------|---------|-------------|
| `db_file` | `~/Documents/bibliography.md` | SQLite database path |
| `log_level` | `"verbose"` | `"verbose"`, `"info"`, `"warn"`, `"error"` |
| `csl.default_style` | `"din-1505-2"` | Key from `csl.styles` |
| `csl.cite_mode` | `"full"` | `"full"`, `"inline"`, `"both"` |
| `csl.inline_format` | `"{author} ({year})"` | Fallback template for inline citations |
| `source_apis.crossref.enabled` | `true` | DOI metadata source |
| `source_apis.openalex.enabled` | `false` | DOI metadata (additional) |
| `keys` | see defaults | Customize all internal keymaps |

Full defaults: `lua/refman/config/defaults.lua`

### Customizing Keymaps

Set `keys` in `setup()` to rebind or disable internal keymaps. Set a key to `nil` to disable it.

```lua
require("refman").setup({
  keys = {
    telescope = {
      toggle_multi = "<Space>",   -- Tab → Space
      delete = nil,               -- disable delete in browser
    },
    tui = {
      quit = "<Esc>",             -- q → Esc
      select = "<Space>",         -- Enter → Space
    },
    detail = {
      close_alt = nil,            -- disable Esc as alternative close
    },
  },
})
```

**Available keys:**

`keys.telescope` — Telescope browser
| Field | Default | Action |
|-------|---------|--------|
| `detail` | `<C-g>` | View entry details |
| `delete` | `<C-d>` | Delete entry |
| `bibliography` | `<C-b>` | Insert formatted bibliography |
| `toggle_multi` | `<Tab>` | Toggle multi-select |

`keys.tui` — Style selection / result TUI
| Field | Default | Action |
|-------|---------|--------|
| `edit` | `e` | Edit / Save & Edit |
| `save` | `s` | Save only |
| `retry` | `r` | Retry fetch |
| `quit` | `q` | Close |
| `select` | `<CR>` | Select highlighted style |
| `select_1`..`select_9` | `1`..`9` | Select style by number |

`keys.detail` — Entry detail view
| Field | Default | Action |
|-------|---------|--------|
| `close` | `q` | Close window |
| `close_alt` | `<Esc>` | Alternative close |
| `edit` | `e` | Open edit buffer |
| `copy_citation` | `c` | Copy citation to buffer |
| `delete` | `d` | Delete entry |

## CSL Styles

Four styles ship in `csl/`: `din-1505-2`, `chicago`, `mla`, `apa`.

Download more from [Zotero Style Repository](https://www.zotero.org/styles) and add to config:

```lua
csl = {
    styles = {
        { name = "My Style", key = "my-style",
          path = "~/.config/refman/styles/my-style.csl", lang = "de-DE" },
    },
}
```

## Minimal Config for Issues

```lua
vim.cmd([[set rtp+=~/.local/share/nvim/lazy/refman.nvim]])
vim.keymap.set("n", "<leader>ri", "<Plug>(RefmanExport)")
```

## Credits

Fetch functions adapted from [calibre](https://github.com/kovidgoyal/calibre) by Kovid Goyal.

## Disclaimer

Built for my personal master's thesis workflow.
AI was used extensively in development.

## License

Copyright (C) 2026 Jan H
This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.
