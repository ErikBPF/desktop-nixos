# Yazi — the file manager, for GUI refugees

**Status:** Guide

Yazi is the primary file manager on the desktop hosts (Hyprland). It runs in a
terminal but behaves like a GUI file manager once your fingers adjust — this
page is the bridge. Nautilus stays installed as a mouse-driven **plan B**.

Config lives in `modules/terminal/yazi.nix` (fleet-wide base) and
`modules/desktop/yazi-desktop.nix` (desktop-only: theme, plugins, GUI keymaps,
the cheatsheet popup). Both are additive — the GUI keys below coexist with
yazi's native `hjkl`/`y`/`x`/`p`, so you can graduate off the training wheels
without relearning anything.

## Open it

| Shortcut | Opens |
|----------|-------|
| `SUPER + E` | **yazi** (in ghostty) — the default |
| double-click a folder | yazi (via mime handler) |
| `SUPER + SHIFT + E` | **Nautilus** — the GUI fallback when you're stuck |
| `SUPER + /` | **Cheatsheet popup** (rofi) — the same table as below |

Inside yazi, `~` opens yazi's own complete keymap reference.

## GUI habit → yazi key

Everything a nautilus user reaches for, mapped 1:1:

| Your GUI reflex | yazi key | Native yazi equivalent |
|-----------------|----------|------------------------|
| Copy | `Ctrl+C` | `y` |
| Cut | `Ctrl+X` | `x` |
| Paste | `Ctrl+V` | `p` (`P` = overwrite) |
| Delete → trash | `Delete` | `d` (`Shift+D` = delete forever) |
| Rename | `F2` | `r` |
| Up / back a folder | `Backspace` or `←` | `h` |
| Open file / enter folder | `Enter` or `→` | `l` |
| First / last item | `Home` / `End` | `gg` / `G` |
| Select multiple | `Space` | `Space`, or `v` for visual range |
| Mouse | double-click opens, scroll scrolls | (on by default) |

There is no `F5` — yazi watches the directory and refreshes itself.

## Power moves (the reason yazi beats a GUI)

| Key | Action |
|-----|--------|
| `Ctrl+D` | Drag the selection into any GUI app (ripdrag) |
| `Ctrl+T` | Open a terminal in the current folder |
| `Ctrl+E` | Extract archive(s) here (ouch) |
| `m` / `'` | Save / jump to a bookmark |
| `M` | Mount / unmount a USB drive |
| `c m` | chmod the selection |
| `/` | Filter/search (`n` / `N` = next / prev) |
| `.` | Toggle hidden files |

Archives preview inline (peek inside without extracting); git status shows as a
column in any repo. Theme is Tokyonight, matching the rest of the desktop.

## Stuck?

`SUPER + SHIFT + E` gives you Nautilus — full mouse GUI, drag-drop, upload
dialogs. It's configured too: right-click → **Open in Terminal** launches
ghostty, and it uses the Tokyonight GTK theme. Use it whenever the TUI fights
you; there's no penalty for bailing.
