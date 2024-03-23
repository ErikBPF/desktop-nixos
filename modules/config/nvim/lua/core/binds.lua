local keymap = vim.keymap.set
local default = { noremap = true, silent = true }
vim.g.mapleader = " "

-- telescope
keymap('n', '<Bslash>', function() require('telescope.builtin').find_files() end, default)
keymap('n', '<A-Bslash>', function() require('telescope.builtin').live_grep() end, default)
keymap('n', '<leader>t', function() require('telescope.command').load_command('todo-comments') end, default)
keymap('n', '<leader>c', function() require('telescope.builtin').spell_suggest() end, default)
keymap('n', '<leader>u', function() require('telescope').extensions.undo.undo() end, default)

-- flash
keymap({ "n", "x", "o" }, 's', function() require("flash").jump() end, default)
keymap({ "n", "x", "o" }, 'S', function() require("flash").treesitter() end, default)

-- fold
keymap('n', 'zR', function() require("ufo").openAllFolds() end, default)
keymap('n', 'zM', function() require("ufo").closeAllFolds() end, default)
keymap('n', 'K', function()
    local winid = require('ufo').peekFoldedLinesUnderCursor()
    if not winid then
        local diag = vim.diagnostic.open_float({
            scope = "cursor",
        })
        if not diag then
            vim.lsp.buf.hover()
        end
    end
end)

-- space
keymap('n', '<leader>l', '<cmd>Lazy<cr>', default)
keymap('n', '<leader>/', '<cmd>CommentToggle<cr>', default)
keymap('v', '<leader>/', "<esc><cmd>'<,'>CommentToggle<cr>", default)

-- lsp
keymap('n', '|', function()
    require('telescope.builtin').lsp_dynamic_workspace_symbols()
end, default)
keymap('n', '<leader>f',
    function()
        vim.lsp.buf.format(); vim.cmd.write()
    end, default)
keymap('n', '<leader>r',
    function() vim.lsp.buf.rename() end, default)
keymap('n', '<leader>s', function()
    require('telescope.builtin').lsp_references()
end, default)
keymap('n', '<leader>d', function()
    require('telescope.builtin').diagnostics()
end, default)

-- ignore this
keymap('v', 'J', ":m '>+1<CR>gv=gv", default)
keymap('v', 'K', ":m '<-2<CR>gv=gv", default)
keymap('x', 'p', '\"_dP', default)

-- buffers
keymap('n', '<A-d>', '<cmd>bd<cr>', default)
keymap('n', '<A-s>', '<cmd>bn<cr>', default)
keymap('n', '<A-w>', '<cmd>bp<cr>', default)
keymap('n', '<A-a>', '<cmd>enew<cr>', default)
