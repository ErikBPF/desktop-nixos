_: {
  # Shared boot wiring for Oracle Cloud VM guests (voyager — x86 micro; telstar —
  # A1 aarch64). Host-specific bits stay in each host's hardware module:
  # fileSystems, disko-vs-in-place layout, the ESP mount point
  # (boot.loader.efi.efiSysMountPoint), boot.loader.grub.configurationLimit, and
  # nixpkgs.hostPlatform. This profile only carries what's identical across OCI
  # guests — learned the hard way while bringing voyager up.
  flake.modules.nixos.profile-oci-guest = {
    lib,
    modulesPath,
    ...
  }: {
    imports = [(modulesPath + "/profiles/qemu-guest.nix")];

    # OCI disk + NIC are virtio; without these initrd modules the guest can't
    # find its root disk or network (a confirmed boot-deaf failure on voyager).
    boot.initrd.availableKernelModules = ["xhci_pci" "virtio_pci" "virtio_scsi" "virtio_blk" "virtio_net" "sd_mod"];

    # Oracle's web/serial console is ttyS0; ttyS0 last so it owns /dev/console.
    # Without this the whole boot is invisible on the OCI console.
    boot.kernelParams = ["console=tty0" "console=ttyS0,115200n8"];

    # OCI VM EFI variables are NOT persisted across stop/start, so the bootloader
    # must live at the removable fallback path (/EFI/BOOT/BOOT<arch>.EFI) and not
    # depend on efibootmgr — GRUB efiInstallAsRemovable does exactly that.
    boot.loader.grub = {
      enable = lib.mkDefault true;
      efiSupport = true;
      efiInstallAsRemovable = true;
      device = "nodev";
    };
    boot.loader.efi.canTouchEfiVariables = false;
  };
}
