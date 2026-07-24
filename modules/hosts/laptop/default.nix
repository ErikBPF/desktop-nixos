{
  config,
  inputs,
  ...
}: let
  m = config.flake.modules;
in {
  configurations.nixos.laptop.module = {
    pkgs,
    modulesPath,
    ...
  }: {
    imports = [
      (modulesPath + "/installer/scan/not-detected.nix")
      inputs.disko.nixosModules.disko
      inputs.sops-nix.nixosModules.sops
      m.nixos.profile-base
      m.nixos.profile-desktop
      m.nixos.laptop-hardware
      m.nixos.laptop-networking
      m.nixos.laptop-syncthing
      m.nixos.laptop-appimage
      m.nixos.first-boot
      m.nixos.alloy
      m.nixos.kepler-nfs
      m.nixos.btrfs-snapshots
      m.nixos.sccache-client
      m.nixos.netbird-client
    ];

    home-manager.users.${config.username} = {
      imports = [
        inputs.nix-colors.homeManagerModules.default
        m.home.profile-desktop
        m.home.monitor-layout-docked
        m.home.laptop-ssh
      ];
      inherit (config) colorScheme;
    };

    system.stateVersion = "25.11";
    nixpkgs.hostPlatform = "x86_64-linux";
    hardware.cpu.intel.updateMicrocode = true;
    boot.kernelPackages = pkgs.linuxPackages_zen;

    boot = {
      kernelParams = ["nohibernate"];
      kernelPatches = [
        {
          name = "audit-default-silent";
          patch = pkgs.writeText "audit-default-silent.patch" ''
            diff --git a/kernel/audit.c b/kernel/audit.c
            --- a/kernel/audit.c
            +++ b/kernel/audit.c
            @@ -81,7 +81,7 @@ static u32	audit_default = AUDIT_OFF;
             static u32	audit_default = AUDIT_OFF;

             /* If auditing cannot proceed, audit_failure selects what happens. */
            -static u32	audit_failure = AUDIT_FAIL_PRINTK;
            +static u32	audit_failure = AUDIT_FAIL_SILENT;

             /* If audit records are to be written to the netlink socket, audit_pid
              * contains the pid of the auditd process and audit_nlk_portid contains
          '';
        }
      ];
      supportedFilesystems = ["ntfs"];
      loader = {
        efi.canTouchEfiVariables = true;
        grub = {
          device = "nodev";
          efiSupport = true;
          enable = true;
          useOSProber = true;
          timeoutStyle = "menu";
          configurationLimit = 3;
        };
        timeout = 1;
      };
    };

    services.btrfs.autoScrub.enable = true;

    # Orion is primary; Kepler contributes capped spillover capacity.
    nix.distributedBuildsOrion.enable = true;
    nix.distributedBuildsKepler.enable = true;

    # Route dev-loop `cargo build` through the shared sccache cache on Orion.
    programs.sccacheClient.enable = true;

    zramSwap = {
      enable = true;
      algorithm = "zstd";
      memoryPercent = 25;
    };

    modules.security.tor-monitor.enable = true;

    # First managed NetBird overlay peer (RFC 2026-07-11-netbird-terraform-
    # declarative-admin §8.5 / G5). Enrols via the TF-minted fleet-server-bootstrap
    # setup-key (sops netbird/setup_key) into the fleet-servers group; overlay on
    # 10.100.0.0/16, coexisting with Tailscale (100.64/10).
    modules.networking.netbird-client.enable = true;

    system.autoUpgrade = {
      enable = true;
      flake = "git+https://github.com/ErikBPF/desktop-nixos?ref=main#laptop";
      operation = "switch";
      flags = ["--show-trace"];
      allowReboot = false;
      dates = "05:00";
      # Stagger off the 05:00 herd (orion cache settles by 04:30).
      randomizedDelaySec = "900";
    };

    services.openssh.enable = true;
  };
}
