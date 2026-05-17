# refman.nvim

Fetch Citations from DOI/ISBN and manage references.

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
