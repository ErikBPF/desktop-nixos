local M = {}
local C = {}

function C.dressing()
    require('dressing').setup {
        input = { enabled = true, win_options = { winblend = 0 } },
        select = { enabled = true, backend = { "telescope" } }
    }
end

table.insert(M, {
    'stevearc/dressing.nvim',
    config = C.dressing,
    event = 'VeryLazy'
})

function C.blankline()
    require('ibl').setup {
        indent = {
            char = '│',
        },
        scope = {
            enabled = true,
            show_start = false,
            show_end = false,
        }
    }
end

table.insert(M, {
    'lukas-reineke/indent-blankline.nvim',
    event = { 'BufReadPre', 'InsertEnter' },
    config = C.blankline
})

function C.twilight()
    require('twilight').setup {
        context = 2,
        dimming = {
            inactive = true
        },
    }
end

table.insert(M, {
    'folke/twilight.nvim',
    config = C.twilight,
    cmd = { 'TwilightEnable', 'TwilightDisable', 'Twilight' }
})

table.insert(M, {
    'lewis6991/gitsigns.nvim',
    event = { 'BufReadPre', 'BufNewFile' },
    config = true
})

table.insert(M, {
    'brenoprata10/nvim-highlight-colors',
    event = { 'BufReadPre', 'BufNewFile' },
    config = true
})

return M
