local M = {}
local C = {}

function C.telescope()
    require('todo-comments').setup()
    require('telescope').setup {
        defaults = require('telescope.themes').get_ivy {
            layout_config = { height = 15 },
            prompt_prefix = "   ",
            selection_caret = " ",
            entry_prefix = " ",
            color_devicons = true,
            winblend = 0,
            vimgrep_arguments = {
                "rg",
                "-L",
                "--color=never",
                "--no-heading",
                "--with-filename",
                "--line-number",
                "--column",
                "--smart-case",
            },
            mappings = {
                i = { ["<esc>"] = require("telescope.actions").close },
            },
        },
        pickers = {
            find_files = {
                find_command = { "fd", "--type", "f", "--strip-cwd-prefix" }
            },
        },
    }
    require("telescope").load_extension("undo")
end

table.insert(M, {
    'nvim-telescope/telescope.nvim',
    lazy = true,
    config = C.telescope,
    dependencies = {
        'nvim-lua/plenary.nvim',
        'debugloop/telescope-undo.nvim',
    },
})

return M
