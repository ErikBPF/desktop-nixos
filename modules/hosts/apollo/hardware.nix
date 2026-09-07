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
    # Mixed Ampere / Blackwell host: Blackwell requires the open kernel modules.
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

    # Retain the RTX 3070's Xid 13/31 mitigation; incoming RTX 5060 Ti cards
    # get their own power ceiling, never the 3070's clock cap. These native
    # controls limit power/boost; they do not program a voltage undervolt.
    systemd.services.nvidia-conservative-clocks = {
      description = "Apply conservative NVIDIA power and clock limits";
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

    # Reserved redundant data pool. Created live 2026-09-05 with
    # the same parted/mdadm/mkfs commands this declaration generates on
    # reinstall (see proposal 2026-09-05-apollo-vm-ram-and-raid1-pool).
    disko.devices.disk = {
      ssd3 = {
        type = "disk";
        device = "/dev/disk/by-id/ata-Samsung_SSD_870_EVO_4TB_S6PJNS0YA01548X";
        content = {
          type = "gpt";
          partitions.data = {
            size = "100%";
            type = "A19D880F-05FC-4D3B-B009-31F1992A73E0";
            content = {
              type = "mdraid";
              name = "microvms";
            };
          };
        };
      };

      ssd4 = {
        type = "disk";
        device = "/dev/disk/by-id/ata-Samsung_SSD_870_EVO_4TB_S6PJNS0YA01573P";
        content = {
          type = "gpt";
          partitions.data = {
            size = "100%";
            type = "A19D880F-05FC-4D3B-B009-31F1992A73E0";
            content = {
              type = "mdraid";
              name = "microvms";
            };
          };
        };
      };
    };

    disko.devices.mdadm.microvms = {
      type = "mdadm";
      level = 1;
      metadata = "1.2";
      extraArgs = ["--homehost=apollo"];
      content = {
        type = "filesystem";
        format = "ext4";
        # Operator decision 2026-09-07: keep MicroVM state on the root pool.
        # Retain this existing mount and array identity; future use is undecided.
        mountpoint = "/mnt/microvms";
      };
    };

    boot.swraid.mdadmConf = ''
      ARRAY /dev/md/microvms metadata=1.2 UUID=e34c6b0a:37d94b6b:8c27d172:8b74ecdc
      MAILADDR root
    '';
  };
}
