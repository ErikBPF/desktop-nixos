_: {
  # Oracle Cloud x86 VM (VM.Standard.E2.1.Micro, 1 GB), provisioned via
  # nixos-infect on a stock Ubuntu cloud image — the second Always-Free AMD
  # micro, sibling of voyager (see docs/proposals/
  # 2026-07-10-vanguard-second-oracle-node.md). Shared OCI-guest boot wiring
  # (virtio initrd, serial console, GRUB removable-install) comes from
  # profile-oci-guest (imported in default.nix); only the in-place disk layout,
  # ESP mount point, and platform are host-specific here.
  flake.modules.nixos.vanguard-hardware = {lib, ...}: {
    networking.useDHCP = lib.mkDefault true;
    nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

    # Ubuntu cloud-image disk layout (as provisioned by OCI); infect rewrites the
    # root partition in place and these labels survive:
    #   /dev/sda1  ext4  cloudimg-rootfs  /
    #   /dev/sda15 vfat  UEFI             /boot/efi
    #   /dev/sda16 ext4  BOOT             /boot
    fileSystems."/" = {
      device = "/dev/disk/by-label/cloudimg-rootfs";
      fsType = "ext4";
    };
    fileSystems."/boot" = {
      device = "/dev/disk/by-label/BOOT";
      fsType = "ext4";
    };
    fileSystems."/boot/efi" = {
      device = "/dev/disk/by-label/UEFI";
      fsType = "vfat";
    };
    boot.loader.efi.efiSysMountPoint = "/boot/efi";

    # 1 GB host: provide swap so activation/builds don't OOM. The swapfile lives
    # on the root fs (already present from the infect bootstrap).
    swapDevices = [
      {
        device = "/var/swapfile";
        size = 4096;
      }
    ];
  };
}
