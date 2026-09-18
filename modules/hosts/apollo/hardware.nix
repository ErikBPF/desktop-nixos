{inputs, ...}: {
  flake.modules.nixos.apollo-hardware = {
    config,
    lib,
    pkgs,
    ...
  }: let
    kernelPkgs = import inputs.nixpkgs-gpu-kernel {
      inherit (pkgs.stdenv.hostPlatform) system;
      config = config.nixpkgs.config;
    };
  in {
    boot.kernelPackages = lib.mkForce kernelPkgs.linuxPackages_7_2;
    boot.initrd.availableKernelModules = ["xhci_pci" "ehci_pci" "ahci" "usb_storage" "sd_mod"];
    # Blackwell-only host: the RTX 5060 Ti pair requires the open kernel modules.
    boot.initrd.kernelModules = ["nvidia"];
    boot.kernelModules = ["kvm-intel" "nvidia" "nvidia_modeset" "nvidia_uvm" "nvidia_drm"];
    boot.blacklistedKernelModules = ["nouveau"];

    services.xserver.videoDrivers = ["nvidia"];
    hardware.graphics = {
      enable = true;
      enable32Bit = true;
    };

    hardware.nvidia = {
      open = true;
      modesetting.enable = true;
      powerManagement.enable = false;
      powerManagement.finegrained = false;
      nvidiaSettings = false;
      nvidiaPersistenced = true;
      package = config.boot.kernelPackages.nvidiaPackages.stable;
    };

    hardware.nvidia-container-toolkit.enable = true;

    # Per-model power ceilings with firmware-managed clocks. Reset old clock
    # locks when applying policy; these controls do not program an undervolt.
    systemd.services.nvidia-conservative-clocks = {
      description = "Apply NVIDIA power limits and restore default clocks";
      wantedBy = ["multi-user.target"];
      after = ["nvidia-persistenced.service"];
      requires = ["nvidia-persistenced.service"];
      path = [config.hardware.nvidia.package.bin];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = builtins.readFile ./_gpu-power.sh;
    };

    # Do not publish GPU container devices if applying their limits failed.
    systemd.services.nvidia-container-toolkit-cdi-generator = {
      after = ["nvidia-conservative-clocks.service"];
      requires = ["nvidia-conservative-clocks.service"];
    };

    environment.systemPackages = [pkgs.nvtopPackages.nvidia];

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

    # Single-disk AI model store. Operator decision 2026-09-18: the second
    # 4 TB disk will never be added, so the two-disk mdadm RAID1 mirror
    # (created live 2026-09-05, see proposal
    # 2026-09-05-apollo-vm-ram-and-raid1-pool) is retired and the surviving
    # disk is used directly as one plain ext4 volume at /mnt/data.
    #
    # The live filesystem was converted in place, not recreated: the old
    # degraded mirror carried 1.1 TiB of models, so only the GPT boundary
    # moved. md's data offset of 264192 sectors on the old /dev/sdb1 put the
    # ext4 superblock at absolute sector 266240, and the single partition now
    # starts exactly there, leaving the filesystem byte-identical.
    # `apollo-ai-storage` in ./default.nix asserts this mountpoint exists.
    #
    # There is no redundancy. The volume holds re-downloadable model weights
    # and experiment scratch only; do not treat it as a backup target.
    # A reinstall formats this partition empty.
    disko.devices.disk = {
      ssd3 = {
        type = "disk";
        device = "/dev/disk/by-id/ata-Samsung_SSD_870_EVO_4TB_S6PJNS0YA01548X";
        content = {
          type = "gpt";
          partitions.data = {
            size = "100%";
            type = "0FC63DAF-8483-4772-8E79-3D69D8477DE4";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/mnt/data";
              # A missing or dirty model disk must never block boot. Without
              # nofail, a failed /mnt/data mount fails local-fs.target, which
              # drops the host into emergency mode with no sshd (observed
              # 2026-09-18 when the retired array device disappeared).
              mountOptions = [
                "nofail"
                "x-systemd.device-timeout=30s"
              ];
            };
          };
        };
      };
    };
  };
}
