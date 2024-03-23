local M = {}
local C = {}

function C.cmp()
    local has_words_before = function()
        unpack = unpack or table.unpack
        local line, col = unpack(vim.api.nvim_win_get_cursor(0))
        return col ~= 0 and
            vim.api.nvim_buf_get_lines(0, line - 1, line, true)[1]:sub(col, col):match("%s") == nil
    end

    require("luasnip.loaders.from_vscode").lazy_load()
    local luasnip = require("luasnip")
    local cmp = require("cmp")
    local kinds = require('util.kinds')

    cmp.setup {
        completion = {
            completeopt = 'menu,menuone,noinsert'
        },
        formatting = {
            fields = { "kind", "abbr", "menu" },
            format = function(_, vim_item)
                vim_item.menu = "(" .. vim_item.kind .. ")"
                vim_item.kind = ' ' .. (kinds[vim_item.kind] or '')
                return vim_item
            end,
        },
        window = {
            completion = {
                border = 'rounded',
                winhighlight = 'Normal:Pmenu,FloatBorder:FloatBorder,CursorLine:PmenuSel,Search:None',
                winblend = 0,
                scrollbar = false,
                col_offset = -3,
                side_padding = 0,
            },
            documentation = {
                border = 'rounded',
                winhighlight = 'Normal:Pmenu,FloatBorder:FloatBorder',
                winblend = 0,
                scrollbar = true,
            }
        },
        mapping = cmp.mapping.preset.insert({
            ["<Tab>"] = cmp.mapping(function(fallback)
                if cmp.visible() then
                    cmp.select_next_item()
                elseif luasnip.expand_or_jumpable() then
                    luasnip.expand_or_jump()
                elseif has_words_before() then
                    cmp.complete()
                else
                    fallback()
                end
            end, { "i", "s" }),
            ["<S-Tab>"] = cmp.mapping(function(fallback)
                if cmp.visible() then
                    cmp.select_prev_item()
                elseif luasnip.jumpable(-1) then
                    luasnip.jump(-1)
                else
                    fallback()
                end
            end, { "i", "s" }),
            ['<C-e>'] = cmp.mapping.scroll_docs(-1),
            ['<C-y>'] = cmp.mapping.scroll_docs(1),
            ['<C-c>'] = cmp.mapping.abort(),
            ["<C-Space>"] = cmp.mapping.confirm({ select = true }),
        }),
        snippet = {
            expand = function(args)
                require('luasnip').lsp_expand(args.body)
            end
        },
        sources = cmp.config.sources({
            { name = 'luasnip' },
            { name = "nvim_lsp" },
            { name = "nvim_lsp_signature_help" },
            { name = "buffer" },
            { name = "path" },
        }),
    }
    cmp.setup.cmdline(':', {
        mapping = cmp.mapping.preset.cmdline(),
        sources = cmp.config.sources({
            { name = 'path' }
        }, {
            { name = 'cmdline' }
        })
    })
end

function C.autopairs()
    local cmp_autopairs = require('nvim-autopairs.completion.cmp')
    local cmp = require('cmp')
    require('nvim-autopairs').setup {}
    cmp.event:on(
        'confirm_done',
        cmp_autopairs.on_confirm_done()
    )
end

table.insert(M, {
    'hrsh7th/nvim-cmp',
    config = C.cmp,
    dependencies = {
        {
            'saadparwaiz1/cmp_luasnip',
            dependencies = {
                'L3MON4D3/LuaSnip',
                'rafamadriz/friendly-snippets',
            }
        },
        'hrsh7th/cmp-nvim-lsp',
        'hrsh7th/cmp-nvim-lsp-signature-help',
        'hrsh7th/cmp-buffer',
        'hrsh7th/cmp-path',
        'hrsh7th/cmp-cmdline',
        {
            'windwp/nvim-autopairs',
            config = C.autopairs,
        }
    },
    event = { 'InsertEnter', 'CmdlineEnter' }
})

return M
