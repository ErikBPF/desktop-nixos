require('colors.highlights')
require('core.autocmds')
require('core.opts')

-- lazy config
local opts = {
    ui = { border = 'rounded' },
    lockfile = vim.fn.stdpath("state") .. "/lazy-lock.json",
    defaults = { lazy = true },
    performance = {
        cache = { enabled = true },
        rtp = {
            disabled_plugins = {
                "tohtml",
                "getscript",
                "getscriptPlugin",
                "gzip",
                "logipat",
                "netrw",
                "netrwPlugin",
                "netrwSettings",
                "netrwFileHandlers",
                "tar",
                "tarPlugin",
                "rrhelper",
                "spellfile",
                "vimball",
                "vimballPlugin",
                "zip",
                "zipPlugin",
                -- "tutor",
                "rplugin",
                "syntax",
                "shada",
                "synmenu",
                "optwin",
                "compiler",
                "bugreport",
                "ftplugin",
            }
        }
    }
}

-- install lazy
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
    vim.fn.system({
        "git",
        "clone",
        "--filter=blob:none",
        "https://github.com/folke/lazy.nvim.git",
        "--branch=stable",
        lazypath,
    })
end
vim.opt.rtp:prepend(lazypath)

-- disable defaults
local default_providers = {
    "node",
    "perl",
    "python3",
    "ruby",
}
for _, provider in ipairs(default_providers) do
    vim.g["loaded_" .. provider .. "_provider"] = 0
end

-- init lazy
require('lazy').setup("plugins", opts)
