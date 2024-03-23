local bases = require('colors.bases')
local pywal = {}

pywal.normal = {
    a = { bg = bases.base0D, fg = bases.background },

    b = { bg = bases.background, fg = bases.base07 },
    c = { bg = bases.background, fg = bases.foreground },
    y = { bg = bases.base01, fg = bases.foreground },
}

pywal.insert = {
    a = { bg = bases.base0B, fg = bases.background },

    b = { bg = bases.background, fg = bases.base07 },
    c = { bg = bases.background, fg = bases.foreground },
    y = { bg = bases.base01, fg = bases.foreground },
}

pywal.visual = {
    a = { bg = bases.base0E, fg = bases.background },

    b = { bg = bases.background, fg = bases.base07 },
    c = { bg = bases.background, fg = bases.foreground },
    y = { bg = bases.base01, fg = bases.foreground },
}

pywal.replace = {
    a = { bg = bases.base09, fg = bases.background },

    b = { bg = bases.background, fg = bases.base07 },
    c = { bg = bases.background, fg = bases.foreground },
    y = { bg = bases.base01, fg = bases.foreground },
}

pywal.inactive = {
    a = { bg = bases.background, fg = bases.base07 },
    c = { bg = bases.background, fg = bases.foreground },
}

return pywal
