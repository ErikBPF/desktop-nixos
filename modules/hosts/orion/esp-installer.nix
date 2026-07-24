{config, ...}: {
  # Destructive migration configuration for the 512M -> 2G ESP operation.
  # Import the real host closure, but force the disko graph down to the boot
  # NVMe. The two SATA data disks must never appear in its generated script.
  configurations.nixos.orion-esp-installer.module = {lib, ...}: {
    imports = [config.configurations.nixos.orion.module];

    disko.devices.disk = lib.mkForce {
      nvme0 = {
        type = "disk";
        device = "/dev/disk/by-id/nvme-Force_MP510_19458242000129183963";
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
    };

    # The migration graph must not own the SATA disks, but the installed system
    # still mounts their existing filesystems by immutable UUID.
    fileSystems."/opt/models" = {
      device = "/dev/disk/by-uuid/88a7f0d3-2fa2-4354-a4cd-8cab451dce85";
      fsType = "ext4";
      options = ["defaults" "noatime"];
    };
    fileSystems."/projects" = {
      device = "/dev/disk/by-uuid/d4511ef9-7f62-4f0f-86d2-ee015344c289";
      fsType = "btrfs";
      options = ["subvol=projects" "compress=zstd" "noatime"];
    };
  };
}
