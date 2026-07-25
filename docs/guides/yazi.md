# Yazi — the file manager, for GUI refugees

**Status:** Guide

Yazi is the terminal file manager on the desktop hosts (Hyprland). Nautilus is
the default keyboard-launched GUI; Yazi remains the directory MIME handler and
the faster terminal option.

Config lives in `modules/terminal/yazi.nix` (fleet-wide base) and
`modules/desktop/yazi-desktop.nix` (desktop-only: theme, plugins, GUI keymaps,
the cheatsheet popup). Both are additive — the GUI keys below coexist with
yazi's native `hjkl`/`y`/`x`/`p`, so you can graduate off the training wheels
without relearning anything.

## Open it

| Shortcut | Opens |
|----------|-------|
| `SUPER + E` | **Nautilus** — opens or focuses the existing window |
| double-click a folder | yazi (via mime handler) |
| `SUPER + SHIFT + E` | **yazi** (in ghostty), resuming its last folder |
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

## Nautilus shortcuts

| Key | Action |
|-----|--------|
| `Ctrl+L` | Edit the current location |
| `Ctrl+T` / `Ctrl+W` | Open / close a tab |
| `Alt+Left` / `Alt+Right` | Back / forward |
| `Alt+Up` | Parent folder |
| `Ctrl+D` | Bookmark the current folder |
| `Ctrl+H` | Toggle hidden files |
| `F2` | Rename |

Right-click → **Open in Terminal** launches ghostty in that folder.

## Path persistence

`SUPER + SHIFT + E` stores Yazi's final directory under
`$XDG_STATE_HOME/yazi/last-cwd` (or `~/.local/state/yazi/last-cwd`) and resumes
there next time. In an existing shell, launch `y`; its `--cwd-file` wrapper
changes that shell's working directory when Yazi exits. A new terminal cannot
inherit the directory of a terminated shell, so the desktop launcher uses the
small state file instead.
