{config, ...}: let
  m = config.flake.modules;
in {
  # Interactive shell quality-of-life: the rich zsh config (plugins, fzf-tab,
  # abbreviations, ported functions), prompt, cross-host history and the
  # file/monitor TUIs. Deliberately NOT in profile-base — headless hosts
  # (archinaut the 1GB printer Pi, the Oracle VMs) get a lean base-home with
  # only a bare zsh login shell + admin tooling, which is what wore out
  # archinaut's SD when the fat base landed on it.
  #
  # profile-desktop imports this, so it lands on the workstations
  # (laptop/pathfinder/orion). A server that wants the same QoL opts in with a
  # single `m.home.profile-interactive` in its host module.
  flake.modules.home.profile-interactive = {...}: {
    imports = [
      m.home.zsh
      m.home.starship
      m.home.atuin
      m.home.yazi
      m.home.zoxide
      m.home.btop
    ];
  };
}
