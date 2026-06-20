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
      # Base SD-image builder only (NOT sd-image-aarch64.nix, which hardcodes
      # u-boot + extlinux). archinaut-kernel-direct supplies the bootloader:
      # GPU-firmware-direct kernel boot, no u-boot — proves out the kernel-direct
      # RFC on a spare SD before the real archinaut card is reflashed.
      (modulesPath + "/installer/sd-card/sd-image.nix")
      inputs.sops-nix.nixosModules.sops
      m.nixos.profile-base
      m.nixos.archinaut-hardware
      m.nixos.archinaut-kernel-direct
    ];

    system.stateVersion = "25.11";

    services.openssh.enable = true;
  };
}
