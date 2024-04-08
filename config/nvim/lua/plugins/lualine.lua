local M = {}
local C = {}

function C.lualine()
    local sep = { left = '', right = '' }
    require('lualine').setup {
        options = {
            theme = require('colors.lualine'),
            globalstatus = true,
            component_separators = { left = '', right = '' },
            section_separators = { left = sep.right, right = sep.left },
        },
        sections = {
            lualine_a = {
                { 'mode', separator = sep },
            },
            lualine_b = { { 'navic', separator = {} } },
            lualine_c = {},
            lualine_x = {},
            lualine_y = { { 'diagnostics' }, { 'filetype' } },
            lualine_z = {
                { 'filename', separator = sep, symbols = {
                    modified = '󰐗',
                    readonly = '󰌾',
                    unnamed = '󰈔',
                } }
            },
        },
        tabline = {},
        extensions = {}
    }
end

function C.navic()
    require("nvim-navic").setup {
        highlight = true,
        separator = '  ',
        icons = require('util.kinds')
    }
end

table.insert(M, {
    'nvim-lualine/lualine.nvim',
    config = C.lualine,
    lazy = false,
    dependencies = {
        'nvim-tree/nvim-web-devicons',
        { 'SmiteshP/nvim-navic', config = C.navic }
    }
})

return M
