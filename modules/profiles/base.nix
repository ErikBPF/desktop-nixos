{config, ...}: let
  m = config.flake.modules;
in {
  flake.modules.nixos.profile-base = {...}: {
    imports = [
      m.nixos.boot-security
      m.nixos.boot-tmpfs
      m.nixos.firewall
      m.nixos.openssh
      m.nixos.resolved
      m.nixos.tailscale
      m.nixos.apparmor
      m.nixos.audit
      m.nixos.issue
      m.nixos.login
      m.nixos.lynis
      m.nixos.pam
      m.nixos.polkit
      m.nixos.sudo
      m.nixos.atuin
      m.nixos.file-systems
      m.nixos.logrotate
      m.nixos.maintenance
      m.nixos.thunderbolt
      m.nixos.xserver
      m.nixos.peripherals
      m.nixos.power
      m.nixos.containers
      m.nixos.vms
      m.nixos.tor-monitor
      m.nixos.common
      m.nixos.user
      m.nixos.packages-shared
      m.nixos.overlays
      m.nixos.sops
      m.nixos.upgrade-health-check
      m.nixos.distributed-builds
    ];
  };

  flake.modules.home.profile-base = {...}: {
    imports = [
      m.home.fish
      m.home.bash
      m.home.starship
      m.home.atuin
      m.home.btop
      m.home.direnv
      m.home.yazi
      m.home.zoxide
      m.home.git
      m.home.gpg
      m.home.nix-tools
      m.home.bat
      m.home.sops
      m.home.ssh
      m.home.packages-shared
    ];
  };
}
