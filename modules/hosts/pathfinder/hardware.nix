_: {
  flake.modules.nixos.pathfinder-hardware = {
    config,
    lib,
    pkgs,
    modulesPath,
    ...
  }: {
    imports = [
      (modulesPath + "/installer/scan/not-detected.nix")
    ];

    # --- Hardware detection ---
    boot.initrd.availableKernelModules = ["xhci_pci" "ahci" "usb_storage" "sd_mod"];
    boot.initrd.kernelModules = ["nvidia"];
    boot.kernelModules = [
      "nvidia"
      "nvidia_modeset"
      "nvidia_uvm"
      "nvidia_drm"
      "kvm-intel"
    ];
    boot.extraModulePackages = [config.boot.kernelPackages.nvidia_x11];
    boot.blacklistedKernelModules = ["nouveau"];

    networking.useDHCP = lib.mkDefault true;
    nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
    hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

    # --- Disko ---
    disko.devices = {
      disk.main = {
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
            luks = {
              size = "100%";
              label = "luks";
              content = {
                type = "luks";
                name = "cryptroot";
                passwordFile = "/tmp/luks-password.txt";
                extraOpenArgs = [
                  "--allow-discards"
                  "--perf-no_read_workqueue"
                  "--perf-no_write_workqueue"
                ];
                settings.crypttabExtraOpts = ["fido2-device=auto" "token-timeout=10"];
                content = {
                  type = "btrfs";
                  extraArgs = ["-L" "nixos" "-f"];
                  subvolumes = {
                    "/root" = {
                      mountpoint = "/";
                      mountOptions = ["subvol=root" "datacow" "compress=zstd" "noatime"];
                    };
                    "/home" = {
                      mountpoint = "/home";
                      mountOptions = ["subvol=home" "datacow" "compress=zstd" "noatime"];
                    };
                    "/nix" = {
                      mountpoint = "/nix";
                      mountOptions = ["subvol=nix" "datacow" "compress=zstd" "noatime"];
                    };
                    "/log" = {
                      mountpoint = "/var/log";
                      mountOptions = ["subvol=log" "datacow" "compress=zstd" "noatime"];
                    };
                  };
                };
              };
            };
          };
        };
      };
    };
    fileSystems."/var/log".neededForBoot = true;

    # --- Intel + Nvidia PRIME GPU ---
    services.xserver.videoDrivers = ["intel" "nvidia"];

    hardware.graphics = {
      enable = true;
      enable32Bit = true;
      extraPackages = with pkgs; [
        intel-media-driver
        libvdpau-va-gl
        nvidia-vaapi-driver
        libva-vdpau-driver
        intel-ocl
        intel-vaapi-driver
      ];
    };

    hardware.nvidia = {
      open = false;
      modesetting.enable = true;
      powerManagement.enable = lib.mkForce true;
      powerManagement.finegrained = false;
      dynamicBoost.enable = lib.mkForce false;
      nvidiaSettings = true;
      nvidiaPersistenced = true;
      package = config.boot.kernelPackages.nvidiaPackages.stable;
      prime = {
        offload = {
          enable = false;
          enableOffloadCmd = false;
        };
        sync.enable = true;
        nvidiaBusId = "PCI:01:00:0";
        intelBusId = "PCI:00:02:0";
      };
    };

    environment.sessionVariables = {
      __NV_PRIME_RENDER_OFFLOAD = "1";
      __NV_PRIME_RENDER_OFFLOAD_PROVIDER = "NVIDIA-G0";
      __GLX_VENDOR_LIBRARY_NAME = "nvidia";
      __VK_LAYER_NV_optimus = "NVIDIA_only";
      LIBVA_DRIVER_NAME = "nvidia";
      NVD_BACKEND = "direct";
      ELECTRON_OZONE_PLATFORM_HINT = "auto";
      NIXOS_OZONE_WL = "1";
    };

    environment.systemPackages = with pkgs; [
      egl-wayland
      nvidia-vaapi-driver
      libvdpau-va-gl
      nvtopPackages.nvidia
      nvtopPackages.intel
    ];
  };
}
