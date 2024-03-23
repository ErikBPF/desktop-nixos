local autocmd = vim.api.nvim_create_autocmd

-- load after enter
autocmd("User", {
    pattern = "VeryLazy",
    callback = function()
        require('core.binds')

        -- twilight
        autocmd("InsertEnter", {
            pattern = "*",
            command = "if empty(&bt) | exec 'TwilightEnable' | exec 'IBLDisable' | endif"
        })
        autocmd("InsertLeave", {
            pattern = "*",
            command = "exec 'TwilightDisable' | exec 'IBLEnable'"
        })

        -- nicities
        autocmd("ExitPre", {
            pattern = "*",
            command = "silent! wa",
        })
        autocmd("VimResized", {
            pattern = "*",
            command = "tabdo wincmd =",
        })
        autocmd("BufWinLeave", {
            pattern = "*",
            command = "silent! mkview!"
        })
    end
})

-- remember line
autocmd("BufWinEnter", {
    pattern = "*",
    command = "silent! loadview",
})

-- zellij
local refresh_events =
{ 'WinEnter', 'BufEnter', 'BufModifiedSet', 'SessionLoadPost', 'FileChangedShellPost', 'VimResized' }
autocmd(refresh_events, {
    pattern = "*",
    callback = function()
        local name = vim.fn.expand("%")
        if vim.api.nvim_buf_get_option(0, 'modified') then
            name = name .. ' [+]'
        end
        _ = io.popen("zellij action rename-pane '" .. name .. "'")
    end
})

