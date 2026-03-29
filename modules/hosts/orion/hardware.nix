_: {
  flake.modules.nixos.orion-hardware = {
    config,
    lib,
    modulesPath,
    ...
  }: {
    imports = [
      (modulesPath + "/installer/scan/not-detected.nix")
    ];

    # --- Hardware detection (AMD Ryzen + Radeon) ---
    boot.initrd.availableKernelModules = ["nvme" "xhci_pci" "ahci" "usb_storage" "sd_mod"];
    boot.kernelModules = ["kvm-amd" "amdgpu"];

    networking.useDHCP = lib.mkDefault true;
    nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
    hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

    # --- Disko: NVMe (btrfs) + 2x SSD (ext4) ---
    disko.devices = {
      disk = {
        nvme0 = {
          type = "disk";
          device = "/dev/nvme0n1"; # placeholder — update after nixos-generate-config in S06
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
        ssd1 = {
          type = "disk";
          device = "/dev/sda"; # placeholder — update after nixos-generate-config in S06
          content = {
            type = "gpt";
            partitions = {
              models = {
                size = "100%";
                content = {
                  type = "filesystem";
                  format = "ext4";
                  mountpoint = "/opt/models";
                  mountOptions = ["defaults" "noatime"];
                };
              };
            };
          };
        };
        ssd2 = {
          type = "disk";
          device = "/dev/sdb"; # placeholder — update after nixos-generate-config in S06
          content = {
            type = "gpt";
            partitions = {
              scratch = {
                size = "100%";
                content = {
                  type = "filesystem";
                  format = "ext4";
                  mountpoint = "/scratch";
                  mountOptions = ["defaults" "noatime"];
                };
              };
            };
          };
        };
      };
    };
    fileSystems."/var/log".neededForBoot = true;

    # --- AMD GPU (minimal stub — full config in S02) ---
    hardware.graphics = {
      enable = true;
      enable32Bit = true;
    };
  };
}
