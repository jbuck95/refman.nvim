# refman.nvim

Fetch Citations from DOI/ISBN and manage references.

## Verify

`:checkhealth refman`

## Dependencies

### System
- `curl` -- for DOI fetching
- `fzf` -- for citation selection UI
- `bash`

### Neovim
- [fzf.vim](https://github.com/junegunn/fzf.vim)

### fetch-metadata (ISBN)

```bash
pipx install <plugin-dir>/scripts/fetch-metadata
```

## Install

### lazy.nvim (minimal)

```lua
{
    "jbuck95/refman.nvim",
    dependencies = {
        {
            "junegunn/fzf.vim",
            dependencies = { "junegunn/fzf" },
        },
    },
    cmd = { "DOI", "ISBN", "RefImport", "RefOpen", "RefExport", "RefMulti" },
    keys = {
        { "<leader>rs", "<Plug>(RefmanImport)", desc = "Save line as citation" },
        { "<leader>ro", "<Plug>(RefmanOpen)", desc = "Open Bibliography Database" },
        { "<leader>ri", "<Plug>(RefmanExport)", desc = "Insert Citation" },
        { "<leader>rm", "<Plug>(RefmanMulti)", desc = "Insert Multiple Citations" },
    },
}
```

### lazy.nvim (with custom config)

```lua
{
    "jbuck95/refman.nvim",
    dependencies = {
        {
            "junegunn/fzf.vim",
            dependencies = { "junegunn/fzf" },
        },
    },
    cmd = { "DOI", "ISBN", "RefImport", "RefOpen", "RefExport", "RefMulti" },
    keys = {
        { "<leader>rs", "<Plug>(RefmanImport)", desc = "Save line as citation" },
        { "<leader>ro", "<Plug>(RefmanOpen)", desc = "Open Bibliography Database" },
        { "<leader>ri", "<Plug>(RefmanExport)", desc = "Insert Citation" },
        { "<leader>rm", "<Plug>(RefmanMulti)", desc = "Insert Multiple Citations" },
    },
    config = function()
        require("refman").setup({
            log_level = "error",
            db_file = "~/my-bibliography.md",
        })
    end,
}
```

## Usage

| Command | Action |
|---------|--------|
| `:DOI` (visual selection) | Convert DOI to citation |
| `:ISBN` (visual selection) | Convert ISBN to citation |
| `:RefImport` | Save current line as bibliography entry |
| `:RefOpen` | Open bibliography database |
| `:RefExport` | Insert single citation via fzf |
| `:RefMulti` | Insert multiple citations via fzf |
| `:RefLog` | Open debug log |

### Keymaps via `<Plug>` mappings

```lua
vim.keymap.set("n", "<leader>rs", "<Plug>(RefmanImport)", { desc = "Save line as citation" })
vim.keymap.set("n", "<leader>ro", "<Plug>(RefmanOpen)", { desc = "Open Bibliography Database" })
vim.keymap.set("n", "<leader>ri", "<Plug>(RefmanExport)", { desc = "Insert Citation" })
vim.keymap.set("n", "<leader>rm", "<Plug>(RefmanMulti)", { desc = "Insert Multiple Citations" })
```

### Lua API

```lua
local refman = require("refman")
refman.import_current_line()
refman.open_database()
refman.export_citation()
refman.export_citations_multi()
refman.convert_doi_citation()
refman.convert_isbn_citation()
refman.setup({ db_file = "~/my-bib.md" })  -- optional
```

## Disclaimer

Some fetch-functions are from:

> https://github.com/kovidgoyal/calibre

### License

Copyright (C) 2026 Jan H
This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.
