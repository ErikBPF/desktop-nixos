{
  config,
  inputs,
  ...
}: let
  m = config.flake.modules;
in {
  configurations.nixos.telstar.module = {...}: {
    imports = [
      inputs.disko.nixosModules.disko
      inputs.sops-nix.nixosModules.sops
      m.nixos.profile-base
      m.nixos.profile-server
      m.nixos.profile-oci-guest
      m.nixos.telstar-hardware
      m.nixos.telstar-networking
      m.nixos.first-boot
    ];

    # Rollback guard: a public-facing host must keep SSH + Tailscale up.
    system.stateVersion = "25.11";
    # Oracle Always-Free Ampere A1 (aarch64, 2 OCPU / 12 GB). Cross-built on Orion.
    nixpkgs.hostPlatform = "aarch64-linux";
  };
}
