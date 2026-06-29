{
  config,
  inputs,
  ...
}: let
  m = config.flake.modules;
in {
  configurations.nixos.voyager.module = {modulesPath, ...}: {
    imports = [
      (modulesPath + "/installer/scan/not-detected.nix")
      inputs.disko.nixosModules.disko
      inputs.sops-nix.nixosModules.sops
      m.nixos.profile-base
      m.nixos.profile-server
      m.nixos.voyager-hardware
      m.nixos.voyager-networking
      m.nixos.containers
      m.nixos.orchestration
      m.nixos.voyager-compose
      m.nixos.first-boot
      m.nixos.alloy
    ];

    # Rollback guard: offsite backups need SSH, Tailscale, and the receiver stack.
    modules.upgradeHealthCheck.criticalUnits = [
      "sshd.service"
      "tailscaled.service"
    ];

    home-manager.users.${config.username}.imports = [
      m.home.profile-base
    ];

    system.stateVersion = "25.11";
    nixpkgs.hostPlatform = "x86_64-linux";
  };
}
