local gen_highlights = function(bases)
    return {

        SignColumn                       = { bg = bases.background },
        CursorLineNr                     = { fg = bases.base0D, bold = true },
        CursorLine                       = { bg = bases.background },
        CursorLineFold                   = { bg = bases.background },
        CursorLineSign                   = { bg = bases.background },
        Comment                          = { fg = bases.base03, italic = true },
        Folded                           = { bold = true, italic = true },
        FoldColumn                       = { bg = bases.background },
        LineNr                           = { fg = bases.base03, },
        LineNrAbove                      = { link = 'LineNr' },
        LineNrBelow                      = { link = 'LineNr' },
        FloatTitle                       = { fg = bases.base05, bg = bases.base00 },
        CursorColumn                     = { bg = bases.background },
        ColorColumn                      = { bg = bases.background },
        StatusLine                       = { bg = bases.background },
        StatusNC                         = { bg = bases.background },
        Normal                           = { fg = bases.base05, bg = bases.base00, },
        Bold                             = { fg = nil, bg = nil, bold = true },
        Debug                            = { fg = bases.base08, bg = nil, },
        Directory                        = { fg = bases.base0D, bg = nil, },
        Error                            = { fg = bases.base08, bg = bases.base00, },
        ErrorMsg                         = { fg = bases.base08, bg = bases.base00, },
        Exception                        = { fg = bases.base08, bg = nil, },
        IncSearch                        = { fg = bases.base01, bg = bases.base09, },
        Italic                           = { fg = nil, bg = nil, },
        Macro                            = { fg = bases.base08, bg = nil, },
        MatchParen                       = { fg = nil, bg = bases.base03, },
        ModeMsg                          = { fg = bases.base0B, bg = nil, },
        MoreMsg                          = { fg = bases.base0B, bg = nil, },
        Question                         = { fg = bases.base0D, bg = nil, },
        Search                           = { fg = bases.base01, bg = bases.base0A, },
        Substitute                       = { fg = bases.base01, bg = bases.base0D, },
        SpecialKey                       = { fg = bases.base03, bg = nil, },
        TooLong                          = { fg = bases.base08, bg = nil, },
        Underlined                       = { fg = bases.base08, bg = nil, },
        Visual                           = { fg = nil, bg = bases.base02, },
        VisualNOS                        = { fg = bases.base08, bg = nil, },
        WarningMsg                       = { fg = bases.base08, bg = nil, },
        WildMenu                         = { fg = bases.base08, bg = bases.base0A, },
        Title                            = { fg = bases.base0D, bg = nil, },
        Conceal                          = { fg = bases.base0D, bg = bases.base00, },
        Cursor                           = { fg = bases.base00, bg = bases.base05, },
        NonText                          = { fg = bases.base03, bg = nil, },
        StatusLineNC                     = { fg = bases.base04, bg = bases.base01, },
        WinBar                           = { fg = bases.base05, bg = nil, },
        WinBarNC                         = { fg = bases.base04, bg = nil, },
        VertSplit                        = { fg = bases.base05, bg = bases.base00, },
        QuickFixLine                     = { fg = nil, bg = bases.base01, },
        PMenu                            = { fg = bases.base05, bg = bases.base01, },
        PMenuSel                         = { fg = nil, bg = bases.base02, },
        TabLine                          = { fg = bases.base03, bg = bases.base01, },
        TabLineFill                      = { fg = bases.base03, bg = bases.base01, },
        TabLineSel                       = { fg = bases.base0B, bg = bases.base01, },
        NormalFloat                      = { fg = bases.base05, bg = bases.base00, },
        FloatBorder                      = { fg = bases.base05, bg = bases.base00, },
        NormalNC                         = { fg = bases.base05, bg = bases.base00, },

        Boolean                          = { fg = bases.base09, bg = nil, },
        Character                        = { fg = bases.base08, bg = nil, },
        Conditional                      = { fg = bases.base0E, bg = nil, },
        Constant                         = { fg = bases.base09, bg = nil, },
        Define                           = { fg = bases.base0E, bg = nil, },
        Delimiter                        = { fg = bases.base0F, bg = nil, },
        Float                            = { fg = bases.base09, bg = nil, },
        Function                         = { fg = bases.base0D, bg = nil, },
        Identifier                       = { fg = bases.base08, bg = nil, },
        Include                          = { fg = bases.base0D, bg = nil, },
        Keyword                          = { fg = bases.base0E, bg = nil, },
        Label                            = { fg = bases.base0A, bg = nil, },
        Number                           = { fg = bases.base09, bg = nil, },
        Operator                         = { fg = bases.base05, bg = nil, },
        PreProc                          = { fg = bases.base0A, bg = nil, },
        Repeat                           = { fg = bases.base0A, bg = nil, },
        Special                          = { fg = bases.base0C, bg = nil, },
        SpecialChar                      = { fg = bases.base0F, bg = nil, },
        Statement                        = { fg = bases.base08, bg = nil, },
        StorageClass                     = { fg = bases.base0A, bg = nil, },
        String                           = { fg = bases.base0B, bg = nil, },
        Structure                        = { fg = bases.base0E, bg = nil, },
        Tag                              = { fg = bases.base0A, bg = nil, },
        Todo                             = { fg = bases.base0A, bg = bases.base01, },
        Type                             = { fg = bases.base0A, bg = nil, },
        Typedef                          = { fg = bases.base0A, bg = nil, },

        -- Diagnostics
        DiagnosticError                  = { fg = bases.base08 },
        DiagnosticWarn                   = { fg = bases.base0E },
        DiagnosticInfo                   = { fg = bases.base05 },
        DiagnosticHint                   = { fg = bases.base0C },

        -- Cmp
        CmpDocumentationBorder           = { fg = bases.base05, bg = nil },
        CmpDocumentation                 = { fg = bases.base05, bg = nil },
        CmpItemAbbr                      = { fg = bases.base05, bg = nil },
        CmpItemAbbrDeprecated            = { fg = bases.base03, strikethrough = true },
        CmpItemAbbrMatch                 = { fg = bases.base0D, },
        CmpItemAbbrMatchFuzzy            = { fg = bases.base0D, },
        CmpItemKindDefault               = { fg = bases.base05, },
        CmpItemMenu                      = { fg = bases.base04, },
        CmpItemKindKeyword               = { fg = bases.base0E, },
        CmpItemKindVariable              = { fg = bases.base08, },
        CmpItemKindConstant              = { fg = bases.base09, },
        CmpItemKindReference             = { fg = bases.base08, },
        CmpItemKindValue                 = { fg = bases.base09, },
        CmpItemKindFunction              = { fg = bases.base0D, },
        CmpItemKindMethod                = { fg = bases.base0D, },
        CmpItemKindConstructor           = { fg = bases.base0D, },
        CmpItemKindClass                 = { fg = bases.base0A, },
        CmpItemKindInterface             = { fg = bases.base0A, },
        CmpItemKindStruct                = { fg = bases.base0A, },
        CmpItemKindEvent                 = { fg = bases.base0A, },
        CmpItemKindEnum                  = { fg = bases.base0A, },
        CmpItemKindUnit                  = { fg = bases.base0A, },
        CmpItemKindModule                = { fg = bases.base05, },
        CmpItemKindProperty              = { fg = bases.base08, },
        CmpItemKindField                 = { fg = bases.base08, },
        CmpItemKindTypeParameter         = { fg = bases.base0A, },
        CmpItemKindEnumMember            = { fg = bases.base0A, },
        CmpItemKindOperator              = { fg = bases.base05, },
        CmpItemKindSnippet               = { fg = bases.base04, },

        -- Navic
        NavicIconsFile                   = { link = 'Structure' },
        NavicIconsModule                 = { link = 'Structure' },
        NavicIconsNamespace              = { link = 'Structure' },
        NavicIconsPackage                = { link = 'Structure' },
        NavicIconsClass                  = { link = 'Structure' },
        NavicIconsMethod                 = { link = 'Function' },
        NavicIconsProperty               = { link = 'Identifier' },
        NavicIconsField                  = { link = 'Identifier' },
        NavicIconsConstructor            = { link = 'Structure' },
        NavicIconsEnum                   = { link = 'Type' },
        NavicIconsInterface              = { link = 'Type' },
        NavicIconsFunction               = { link = 'Function' },
        NavicIconsVariable               = { link = 'Identifier' },
        NavicIconsConstant               = { link = 'Constant' },
        NavicIconsString                 = { link = 'String' },
        NavicIconsNumber                 = { link = 'Number' },
        NavicIconsBoolean                = { link = 'Boolean' },
        NavicIconsArray                  = { link = 'Structure' },
        NavicIconsObject                 = { link = 'Structure' },
        NavicIconsKey                    = { link = 'Identifier' },
        NavicIconsNull                   = { link = 'Special' },
        NavicIconsEnumMember             = { link = 'Identifier' },
        NavicIconsStruct                 = { link = 'Structure' },
        NavicIconsEvent                  = { link = 'Type' },
        NavicIconsOperator               = { link = 'Operator' },
        NavicIconsTypeParameter          = { link = 'Type' },
        NavicText                        = { fg = bases.base04 },
        NavicSeparator                   = { fg = bases.base03 },

        -- Blankline
        IBLScope                         = { fg = bases.base04 },
        IBLIndent                        = { fg = bases.base02 },

        -- Treesitter
        TSAnnotation                     = { fg = bases.base0F, },
        TSAttribute                      = { fg = bases.base0A, },
        TSBoolean                        = { fg = bases.base09, },
        TSCharacter                      = { fg = bases.base08, },
        TSComment                        = { fg = bases.base03, italic = true },
        TSConstructor                    = { fg = bases.base0D, },
        TSConditional                    = { fg = bases.base0E, },
        TSConstant                       = { fg = bases.base09, },
        TSConstBuiltin                   = { fg = bases.base09, italic = true },
        TSConstMacro                     = { fg = bases.base08, },
        TSError                          = { fg = bases.base08, },
        TSException                      = { fg = bases.base08, },
        TSField                          = { fg = bases.base05, },
        TSFloat                          = { fg = bases.base09, },
        TSFunction                       = { fg = bases.base0D, },
        TSFuncBuiltin                    = { fg = bases.base0D, italic = true },
        TSFuncMacro                      = { fg = bases.base08, },
        TSInclude                        = { fg = bases.base0D, },
        TSKeyword                        = { fg = bases.base0E, },
        TSKeywordFunction                = { fg = bases.base0E, },
        TSKeywordOperator                = { fg = bases.base0E, },
        TSLabel                          = { fg = bases.base0A, },
        TSMethod                         = { fg = bases.base0D, },
        TSNamespace                      = { fg = bases.base08, },
        TSNone                           = { fg = bases.base05, },
        TSNumber                         = { fg = bases.base09, },
        TSOperator                       = { fg = bases.base05, },
        TSParameter                      = { fg = bases.base05, },
        TSParameterReference             = { fg = bases.base05, },
        TSProperty                       = { fg = bases.base05, },
        TSPunctDelimiter                 = { fg = bases.base0F, },
        TSPunctBracket                   = { fg = bases.base05, },
        TSPunctSpecial                   = { fg = bases.base05, },
        TSRepeat                         = { fg = bases.base0E, },
        TSString                         = { fg = bases.base0B, },
        TSStringRegex                    = { fg = bases.base0C, },
        TSStringEscape                   = { fg = bases.base0C, },
        TSSymbol                         = { fg = bases.base0B, },
        TSTag                            = { fg = bases.base08, },
        TSTagDelimiter                   = { fg = bases.base0F, },
        TSText                           = { fg = bases.base05, },

        TSEmphasis                       = { fg = bases.base09, italic = true, },
        TSUnderline                      = { fg = bases.base00, },
        TSStrike                         = { fg = bases.base00, strikethrough = true, },
        TSTitle                          = { fg = bases.base0D, },
        TSLiteral                        = { fg = bases.base09, },
        TSURI                            = { fg = bases.base09, },
        TSType                           = { fg = bases.base0A, },
        TSTypeBuiltin                    = { fg = bases.base0A, italic = true },
        TSVariable                       = { fg = bases.base08, },
        TSVariableBuiltin                = { fg = bases.base08, italic = true },

        -- Lsp
        LspInlayHint                     = { fg = bases.base03 },
        LspDiagnosticsDefaultError       = { link = 'DiagnosticError' },
        LspDiagnosticsDefaultWarning     = { link = 'DiagnosticWarn' },
        LspDiagnosticsDefaultInformation = { link = 'DiagnosticInfo' },
        LspDiagnosticsDefaultHint        = { link = 'DiagnosticHint' },

        -- GitSigns
        GitSignsAdd                      = { fg = bases.base0B },
        GitSignsDelete                   = { fg = bases.base0E },
        GitSignsChange                   = { fg = bases.base08 },
        GitSignsUntracked                = { fg = bases.base0D },

        -- Telescope
        TelescopeBorder                  = { link = 'FloatBorder' },
        TelescopeTitle                   = { link = 'FloatTitle' },
        TelescopeNormal                  = { link = 'NormalFloat' },
        TelescopeSelection               = { link = 'PmenuSel' },
        TelescopePromptPrefix            = { link = 'FloatTitle' },

        -- Lsp
        LspFloatWinNormal                = { bg = bases.base00 },
        LspFloatWinBorder                = { fg = bases.base05 },
    }
end

local bases = require('colors.bases')
local base_highlights = gen_highlights(bases)
for group, properties in pairs(base_highlights) do
    vim.api.nvim_set_hl(0, group, properties)
end
