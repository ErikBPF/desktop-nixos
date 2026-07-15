{config, ...}: let
  m = config.flake.modules;
in {
  # Interactive shell quality-of-life for EVERY host: the rich zsh config
  # (fzf-tab, aliases, ported functions), the starship prompt,
  # and the file/dir/monitor TUIs. Imported by profile-base's home (below), so
  # it lands fleet-wide — servers included.
  #
  # atuin is deliberately NOT here. Its local history DB writes wear flash
  # storage (the atuin DB on the 1GB Pi was killing archinaut's SD), so it is an
  # opt-in — profile-desktop (workstations) and the orion dev container pull
  # m.home.atuin explicitly; headless flash-backed hosts (archinaut, Oracle VMs)
  # get the rest of the QoL but never atuin.
  flake.modules.home.profile-interactive = {...}: {
    imports = [
      m.home.zsh
      m.home.starship
      m.home.yazi
      m.home.zoxide
      m.home.btop
    ];
  };
}
