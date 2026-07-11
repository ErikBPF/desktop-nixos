# Terminal tooling additions — qutebrowser, basalt, tmux, grafatui

**Status:** ✅ Implemented (2026-07-11) — switched on laptop; qutebrowser, basalt, tmux, and grafatui binaries live in the user profile, tmux config linked. Was "not yet switched" on 2026-07-10; the pending `switch-laptop` landed 2026-07-11.

> All seven gates ruled 2026-07-10 (§10); modules written and wired.
> `just lint`, `just fmt-check`, `just dry laptop` and `just dry orion` all pass.
> Nothing deployed yet — a `switch-laptop` (and orion sandbox rebuild) is the
> remaining step. Graduates to `implemented/` after the post-switch smoke checks
> in §8 pass.

### Ruled gates (2026-07-10)

- **G1** → session-wide Wayland Qt env; no per-launcher wrapper.
- **G2** → basalt reads Obsidian's own config; module is **package-only**.
- **G3** → `rustPlatform.buildRustPackage` in `modules/overlays.nix`. Source is
  **`fetchFromGitHub` tag `v0.1.10`** (crates.io tops out at 0.1.9; the release
  is GitHub-only). Hashes filled: src `sha256-bFCq0Pz…`, cargo `sha256-7ReVLNt…`.
  `nix build …pkgs.grafatui` succeeds.
- **G4** → **no change needed.** ACL rule 7 in `homelab-iac`
  `tailscale/acl/policy.hujson:73` already grants
  `laptop → discovery:3100,9090` (the Alloy metrics grant); port 9090 is
  port-level so it covers grafatui's read queries. No tofu apply.
- **G5** → `fleet-metrics` launcher imports a pinned snapshot of servarr's
  `fleet-status` dashboard, vendored at
  `modules/terminal/_grafatui/fleet-status.json` (D9 publish-and-pin).
- **G6** → stylix `tmux` target (base16), enabled centrally in
  `modules/desktop/stylix.nix` so `tmux.nix` stays portable to the no-stylix
  orion microvm. No resurrect/continuum (herdr owns session persistence).
- **G7** → `m.home.tmux` imported into `modules/hosts/orion/dev-sandbox.nix`.

> The module sketches below are the design record; the as-built files
> (`modules/browser/qutebrowser.nix`, `modules/desktop/basalt.nix`,
> `modules/terminal/{tmux,grafatui}.nix`, overlay + stylix targets) may differ
> in small ways (e.g. stylix targets moved to the central module per G6).

## 0. Scope note — `herdr` is already shipped

The original request bundled `herdr`, but it is **already fully wired** and needs
no work here:

- flake input `herdr.url = "github:ogulcancelik/herdr/v0.7.1"` (`flake.nix:109`),
- module `modules/dev/herdr.nix` (`flake.modules.home.herdr`, declarative
  `config.toml`, launchers for claude/codex/opencode/hermes),
- imported in `modules/profiles/desktop.nix:66` **and** the orion dev-sandbox
  (`modules/hosts/orion/dev-sandbox.nix:159`).

This RFC therefore covers only the **four new tools**: qutebrowser, basalt, tmux,
grafatui.

## 1. Locked decisions

| # | Decision | Choice | Consequence |
|---|----------|--------|-------------|
| L1 | Metrics-TUI tool | **grafatui** (not grafterm) | grafterm (nixpkgs 0.2.0) is dead upstream since 2019. grafatui (`crates.io` v0.1.10, Jun 2026, actively maintained, native Grafana-dashboard import) is **not** in nixpkgs → needs an in-repo derivation (§5). |
| L2 | Delivery | **RFC first** | This doc. Implementation lands only after the §6 gates are ruled. |

## 2. Motivation

Four terminal-first tools that fit the existing workstation dev loop (all land on
`profile-desktop` → the `laptop` host, alongside the yazi/ghostty/btop/herdr set):

- **qutebrowser** — keyboard-driven browser; complements the GUI brave/firefox
  already present, no mouse dependency for quick lookups from a tiling WM.
- **basalt** — Obsidian TUI; read/edit the vault the repo already manages via
  `obsidian` + `obsidian-sync` without launching the Electron GUI.
- **tmux** — terminal multiplexer for plain SSH / non-herdr sessions and nesting
  (herdr owns the AI-agent panes; tmux is the general-purpose multiplexer).
- **grafatui** — glance at fleet Prometheus (`http://discovery:9090`) from the
  terminal without opening the Grafana web UI.

Goal: each is a self-contained `flake.modules.home.<name>` module imported by
`profiles/desktop.nix`, themed off the base16 SSOT (stylix target or
`colorScheme.palette`, matching the repo's per-app convention), verified with
`just dry laptop` before any switch.

## 3. qutebrowser

nixpkgs `qutebrowser` 3.7.0; home-manager `programs.qutebrowser`
(`settings`/`keyBindings`/`searchEngines`/`quickmarks`/`extraConfig`). Stylix has
a `qutebrowser` target → theme from the same base16 scheme.

**Draft** `modules/browser/qutebrowser.nix`:

```nix
_: {
  flake.modules.home.qutebrowser = {...}: {
    programs.qutebrowser = {
      enable = true;
      loadAutoconfig = false;              # config.py is the SSOT, not the GUI
      searchEngines = {
        DEFAULT = "https://duckduckgo.com/?q={}";
        nw = "https://mynixos.com/search?q={}";
        gh = "https://github.com/search?q={}&type=repositories";
      };
      settings = {
        content.blocking.enabled = true;
        # dark preference; stylix handles the chrome palette
        colors.webpage.preferred_color_scheme = "dark";
        tabs.show = "multiple";
      };
    };
    stylix.targets.qutebrowser.enable = true;   # base16 chrome theming
  };
}
```

**Wayland note (gate G1):** on the Hyprland session qutebrowser wants
`QT_QPA_PLATFORM=wayland`. Options: rely on the session-wide portal env already
set for Qt (stylix `targets.qt` is on), or wrap the launcher with the env
explicitly. Decide whether the existing session env already covers it before
adding a wrapper (avoid the XWayland blur otherwise).

## 4. basalt (Obsidian TUI)

nixpkgs `basalt` 0.12.6 = erikjuhani's `basalt-tui`. **No** home-manager module →
`home.packages` + an optional TOML config (basalt ships no default config file).
Pairs with the existing `obsidian` / `obsidian-sync` modules.

**Draft** `modules/desktop/basalt.nix` (sibling of `obsidian.nix`):

```nix
_: {
  flake.modules.home.basalt = {pkgs, ...}: let
    tomlFormat = pkgs.formats.toml {};
  in {
    home.packages = [pkgs.basalt];
    # Optional — omit entirely to let basalt autodetect the Obsidian vault.
    xdg.configFile."basalt/config.toml".source =
      tomlFormat.generate "basalt-config.toml" {
        # editor / theme keys per basalt docs — fill from the vault gate G2
      };
  };
}
```

**Gate G2 — vault path.** Confirm how basalt discovers the vault: does it read
Obsidian's own config (auto), or must the vault dir be pinned in `config.toml`?
Cross-check against where `obsidian-sync` places the vault on `laptop`. If
autodetect works, ship **package-only** (drop the `xdg.configFile`).

## 5. grafatui (metrics TUI) — needs packaging

Rust/Cargo, `crates.io` `grafatui` v0.1.10. CLI: `--prometheus-url <url>`,
optional `--grafana-json <dashboard.json>`, TOML config + built-in themes. Not in
nixpkgs.

**Packaging (gate G3).** Add a derivation and expose it via the existing
`modules/overlays.nix` overlay (precedent: quickshell/claude-code entries):

```nix
# in the overlay's (final: _prev: { … }) block
grafatui = final.rustPlatform.buildRustPackage rec {
  pname = "grafatui";
  version = "0.1.10";
  src = final.fetchCrate {
    inherit pname version;
    hash = "sha256-AAAA…";       # TODO fill on first build
  };
  cargoHash = "sha256-BBBB…";    # TODO fill on first build
};
```

Then a thin home module wires the binary + a preset launcher:

**Draft** `modules/terminal/grafatui.nix`:

```nix
_: {
  flake.modules.home.grafatui = {pkgs, ...}: {
    home.packages = [
      pkgs.grafatui
      # preset launcher → fleet Prometheus over the tailnet (MagicDNS)
      (pkgs.writeShellScriptBin "fleet-metrics" ''
        exec ${pkgs.grafatui}/bin/grafatui --prometheus-url http://discovery:9090 "$@"
      '')
    ];
  };
}
```

**Gate G4 — tailnet ACL.** `http://discovery:9090` is the Alloy remote-write
receiver (`modules/services/alloy.nix:124`). Today the tailnet ACL grants
`<scraper-host> -> discovery:9090`; `laptop` is not necessarily in that grant.
Landing grafatui on `laptop` may need an ACL edit in `homelab-iac` (D9: network
is that repo's concern). Confirm before relying on the launcher.

**Gate G5 — dashboard import (optional).** grafatui can import a Grafana dashboard
JSON. The fleet already has 15 provisioned dashboards
(`2026-06-29-grafana-fleet-monitoring`). Decide whether to point `--grafana-json`
at one of those (and how to vendor it) or start with raw PromQL only.

## 6. tmux

nixpkgs `tmux` 3.7b; home-manager `programs.tmux` with declarative `plugins`.
Stylix has a `tmux` target.

**Draft** `modules/terminal/tmux.nix`:

```nix
_: {
  flake.modules.home.tmux = {pkgs, ...}: {
    programs.tmux = {
      enable = true;
      shell = "${pkgs.fish}/bin/fish";     # matches the fleet default shell
      keyMode = "vi";
      mouse = true;
      baseIndex = 1;
      escapeTime = 10;
      historyLimit = 50000;
      terminal = "tmux-256color";
      plugins = with pkgs.tmuxPlugins; [
        sensible
        vim-tmux-navigator
        yank
        # resurrect + continuum: opt-in per gate G6
      ];
    };
    stylix.targets.tmux.enable = true;      # base16, not catppuccin (SSOT)
  };
}
```

**Gate G6 — persistence + theme.**
- resurrect/continuum add session save/restore but write state; decide if that is
  wanted on a laptop that already has herdr session persistence.
- **Theme:** use `stylix.targets.tmux` (keeps the base16 SSOT) **rather than** the
  catppuccin plugin, to match how btop/yazi/ghostty derive from `colorScheme`.
  Pick one — do not layer both.
- **herdr overlap:** herdr is the AI-agent multiplexer; tmux is for everything
  else. Confirm no prefix-key clash if the two are ever nested.

## 7. Host scope

| Module | `profile-desktop` (laptop) | orion dev-sandbox | Notes |
|--------|:--:|:--:|-------|
| qutebrowser | ✅ | — | GUI browser; desktop only |
| basalt | ✅ | — | needs the obsidian vault (laptop) |
| tmux | ✅ | ➕ maybe | could also suit the orion remote sandbox — gate G7 |
| grafatui | ✅ | — | needs tailnet reach to discovery:9090 |

**Gate G7:** decide whether tmux (and only tmux) should also import into
`modules/hosts/orion/dev-sandbox.nix` (it already imports `m.home.herdr`).

## 8. Verification plan

Per `CLAUDE.md` "Verify changes":

1. `git add` the 4 new files **before** any nix eval (untracked = invisible to the
   flake).
2. `just lint && just fmt-check`.
3. `just dry laptop` (or `nix build .#nixosConfigurations.laptop.…toplevel --dry-run`)
   — must eval clean with the new home modules.
4. grafatui only: first real build fills the two `TODO` hashes (G3); iterate until
   `nix build` of the overlay attr succeeds.
5. Post-`switch` smoke: launch each binary once; `fleet-metrics` must connect to
   discovery:9090 (validates G4).
6. `just docs-check` after graduating this doc.

## 9. Rollout order

1. qutebrowser, basalt, tmux — pure nixpkgs, no packaging risk. Land first, one
   commit each or one grouped `feat(desktop): add qutebrowser/basalt/tmux` commit.
2. grafatui — separate commit after the overlay derivation builds and G3/G4 are
   settled (packaging + ACL are the only real unknowns).

## 10. Open gates summary

| Gate | Question |
|------|----------|
| G1 | qutebrowser Wayland env — session-wide or per-launcher wrapper? |
| G2 | basalt vault — autodetect (package-only) or pin in `config.toml`? |
| G3 | grafatui derivation — `fetchCrate` + fill `cargoHash`; overlay vs `pkgs/`. |
| G4 | tailnet ACL grant `laptop -> discovery:9090` (homelab-iac). |
| G5 | grafatui — import an existing Grafana dashboard JSON, or PromQL-only? |
| G6 | tmux — resurrect/continuum yes/no; stylix theme (not catppuccin). |
| G7 | tmux also into orion dev-sandbox? |

---

**Sources:** [home-manager `programs.qutebrowser`](https://github.com/nix-community/home-manager/blob/master/modules/programs/qutebrowser.nix),
[qutebrowser NixOS Wiki](https://nixos.wiki/wiki/Qutebrowser),
[basalt (erikjuhani)](https://github.com/erikjuhani/basalt),
[grafatui (fedexist)](https://github.com/fedexist/grafatui),
[catppuccin/tmux](https://github.com/catppuccin/tmux),
[tmux + home-manager (Haseeb Majid)](https://haseebmajid.dev/posts/2023-07-10-setting-up-tmux-with-nix-home-manager/).
