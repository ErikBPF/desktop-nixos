pragma Singleton
import QtQuick

QtObject {
    // Colors — Tokyo Night Dark via nix-colors (loaded from theme.json)
    readonly property color base00: "#1a1b26"
    readonly property color base01: "#16161e"
    readonly property color base02: "#2f3549"
    readonly property color base03: "#444b6a"
    readonly property color base04: "#787c99"
    readonly property color base05: "#a9b1d6"
    readonly property color base06: "#cbccd1"
    readonly property color base07: "#d5d6db"
    readonly property color base08: "#c0caf5"
    readonly property color base09: "#a9b1d6"
    readonly property color base0A: "#0db9d7"
    readonly property color base0B: "#9ece6a"
    readonly property color base0C: "#b4f9f8"
    readonly property color base0D: "#2ac3de"
    readonly property color base0E: "#bb9af7"
    readonly property color base0F: "#f7768e"

    // Semantic aliases
    readonly property color background: base00
    readonly property color surface: base01
    readonly property color selection: base02
    readonly property color subtle: base03
    readonly property color dimText: base04
    readonly property color text: base05
    readonly property color brightText: base06
    readonly property color accent: base0D
    readonly property color success: base0B
    readonly property color warning: base0A
    readonly property color error: base0F
    readonly property color special: base0E
    readonly property color info: base0C

    // Fonts — match system config from fonts.nix
    readonly property string fontMono: "JetBrainsMono Nerd Font"
    readonly property string fontSans: "Noto Sans"
    readonly property string fontSerif: "Noto Serif"

    // Bar metrics
    readonly property int barHeight: 32
    readonly property int barFontSize: 11
    readonly property int barIconSize: 13
    readonly property real barOpacity: 0.0
    readonly property int barRadius: 10
    readonly property int pillHeight: 24
    readonly property int pillRadius: 8
}
