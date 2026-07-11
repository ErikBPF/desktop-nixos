_: {
  # basalt — Obsidian TUI (erikjuhani/basalt-tui). Read/edit the vault the
  # `obsidian` + `obsidian-sync` modules already manage, without the Electron
  # GUI. Package-only: basalt discovers the vault from Obsidian's own config
  # (gate G2), so no declarative config.toml is needed.
  flake.modules.home.basalt = {pkgs, ...}: {
    home.packages = [pkgs.basalt];
  };
}
