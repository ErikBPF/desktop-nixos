local M = {}
local C = {}

function C.flash()
    require('flash').setup {
        modes = { char = { highlight = { backdrop = false } } }
    }
end

table.insert(M, {
    "folke/flash.nvim",
    event = "VeryLazy",
    config = C.flash,
})

function C.comment()
    require('nvim_comment').setup {
        create_mappings = false
    }
end

table.insert(M, {
    'terrortylor/nvim-comment',
    config = C.comment,
    cmd = 'CommentToggle'
})

table.insert(M, {
    'echasnovski/mini.bracketed',
    config = true,
    event = 'VeryLazy',
})

return M
