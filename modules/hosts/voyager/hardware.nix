_: {
  flake.modules.nixos.voyager-hardware = {
    lib,
    modulesPath,
    ...
  }: {
    imports = [
      (modulesPath + "/profiles/qemu-guest.nix")
    ];

    # Oracle Cloud VM: single 46.6G EFI boot volume exposed as /dev/sda.
    # nixos-anywhere will wipe this disk.
    boot.initrd.availableKernelModules = ["xhci_pci" "virtio_pci" "virtio_scsi" "sd_mod"];

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

    boot.loader = {
      efi.canTouchEfiVariables = true;
      systemd-boot = {
        enable = true;
        # 512M ESP: cap generations low so kernel+initrd copies never overflow
        # /boot (cf. kepler ESP-overflow lesson).
        configurationLimit = 2;
      };
    };
  };
}
