_: {
  flake.modules.nixos.apollo-hardware = {
    config,
    lib,
    ...
  }: {
    boot.initrd.availableKernelModules = ["xhci_pci" "ehci_pci" "ahci" "usb_storage" "sd_mod"];
    boot.kernelModules = ["kvm-intel"];

    networking.useDHCP = lib.mkDefault false;
    hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

    # Observed 2026-08-29. Both old installations are intentionally replaced by
    # one rebuildable Btrfs RAID1 system. The installer USB is not represented.
    disko.devices.disk = {
      ssd1 = {
        type = "disk";
        device = "/dev/disk/by-id/ata-KINGSTON_SA400S37240G_50026B7783B9EE25";
        content = {
          type = "gpt";
          partitions.mirror = {
            size = "100%";
            content.type = "btrfs";
          };
        };
      };

      ssd2 = {
        type = "disk";
        device = "/dev/disk/by-id/ata-KINGSTON_SA400S37240G_50026B76831D2524";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              label = "boot";
              name = "ESP";
              size = "2G";
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
                extraArgs = [
                  "-L"
                  "nixos"
                  "-f"
                  "-d"
                  "raid1"
                  "-m"
                  "raid1"
                  "/dev/disk/by-id/ata-KINGSTON_SA400S37240G_50026B7783B9EE25-part1"
                ];
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
    };

    fileSystems."/var/log".neededForBoot = true;
  };
}
