_: {
  # Oracle Cloud Always-Free Ampere A1 VM (VM.Standard.A1.Flex, 2 OCPU / 12 GB,
  # aarch64). Unlike the 1 GB x86 micro, A1 has ample RAM, so this host installs
  # cleanly via nixos-anywhere (kexec works) + disko — no in-place infect, no
  # image import. Closure cross-builds on Orion (binfmt). Shared OCI-guest boot
  # wiring (virtio initrd, serial console, GRUB removable-install) comes from
  # profile-oci-guest (imported in default.nix); only the disko layout, ESP mount
  # point, generation cap, and platform are host-specific here.
  flake.modules.nixos.telstar-hardware = {lib, ...}: {
    networking.useDHCP = lib.mkDefault true;
    nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";

    disko.devices.disk.sda = {
      type = "disk";
      device = "/dev/sda";
      content = {
        type = "gpt";
        partitions = {
          ESP = {
            label = "boot";
            name = "ESP";
            size = "512M";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = ["defaults"];
            };
          };
          root = {
            size = "100%";
            content = {
              type = "btrfs";
              extraArgs = ["-L" "nixos" "-f"];
              subvolumes = {
                "/root" = {
                  mountpoint = "/";
                  mountOptions = ["subvol=root" "compress=zstd" "noatime"];
                };
                "/home" = {
                  mountpoint = "/home";
                  mountOptions = ["subvol=home" "compress=zstd" "noatime"];
                };
                "/nix" = {
                  mountpoint = "/nix";
                  mountOptions = ["subvol=nix" "compress=zstd" "noatime"];
                };
                "/log" = {
                  mountpoint = "/var/log";
                  mountOptions = ["subvol=log" "compress=zstd" "noatime"];
                };
              };
            };
          };
        };
      };
    };

    fileSystems."/var/log".neededForBoot = true;

    # disko mounts the ESP at /boot, so GRUB installs there (not the /boot/efi
    # default). 512M ESP → cap generations so kernels+initrds don't overflow it.
    boot.loader.efi.efiSysMountPoint = "/boot";
    boot.loader.grub.configurationLimit = 5;
  };
}
