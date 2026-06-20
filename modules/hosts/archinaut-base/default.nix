{
  config,
  inputs,
  ...
}: let
  m = config.flake.modules;
in {
  # Minimal RESCUE / FALLBACK image for the archinaut RPi3.
  #
  # Same hardware + base profile as the full `archinaut` host, but WITHOUT the
  # print stack (klipper-host) and WITHOUT alloy — the two services that make
  # the full image thrash a 1 GB Pi on first boot. This image boots light and
  # holds SSH, giving a stable foothold to converge from (nixos-rebuild
  # switch / nixos-anywhere --target-host) when the full image wedges.
  #
  # Same MAC as the full host, so it lands on the same DHCP leases
  # (.187 wired / .225 wifi). sshd on 2222 (see modules/networking/openssh.nix).
  configurations.nixos.archinaut-base.module = {modulesPath, ...}: {
    imports = [
      (modulesPath + "/installer/sd-card/sd-image-aarch64.nix")
      inputs.sops-nix.nixosModules.sops
      m.nixos.profile-base
      m.nixos.archinaut-hardware
    ];

    system.stateVersion = "25.11";

    services.openssh.enable = true;
  };
}
