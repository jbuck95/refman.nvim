# refman.nvim

Fetch Citations from DOI/ISBN and manage references.

## Verify

`:checkhealth refman`

## Dependencies

### System
- `curl` — for DOI fetching
- `fzf` — for citation selection UI
- `bash`

### Neovim
- [fzf.vim](https://github.com/junegunn/fzf.vim)

### fetch-metadata (ISBN)

```bash
pipx install <plugin-dir>/scripts/fetch-metadata
```

## Install (lazy)

```lua
return {
    "jbuck95/refman.nvim",
    dependencies = {
        {
            "junegunn/fzf.vim",
            dependencies = { "junegunn/fzf" },
        },
    },
    cmd = { "DOI", "ISBN", "RefImport", "RefOpen", "RefExport", "RefMulti" },
    keys = {
        { "<leader>rs", desc = "Save line as citation" },
        { "<leader>ro", desc = "Open Bibliography Database" },
        { "<leader>ri", desc = "Insert Citation" },
        { "<leader>rm", desc = "Insert Multiple Citations" },
    },
    config = function()
        local refman = require("refman")
        refman.setup()

        vim.keymap.set("n", "<leader>rs", refman.import_current_line, { desc = "Save line as citation" })
        vim.keymap.set("n", "<leader>ro", refman.open_database, { desc = "Open Bibliography Database" })
        vim.keymap.set("n", "<leader>ri", refman.export_citation, { desc = "Insert Citation" })
        vim.keymap.set("n", "<leader>rm", refman.export_citations_multi, { desc = "Insert Multiple Citations" })
    end,
}
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
