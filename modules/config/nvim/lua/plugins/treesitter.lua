local M = {}
local C = {}

function C.treesitter()
    require('nvim-treesitter.configs').setup {
        auto_install = true,
        highlight = {
            enable = true,
            additional_vim_regex_highlighting = false
        }
    }
end

table.insert(M, {
    'folke/todo-comments.nvim',
    event = { 'BufReadPre', 'BufNewFile' },
    config = true,
    dependencies = {
        {
            'nvim-treesitter/nvim-treesitter',
            config = C.treesitter,
            dependencies = {
                "nushell/tree-sitter-nu",
            }
        },
    }
})

return M
