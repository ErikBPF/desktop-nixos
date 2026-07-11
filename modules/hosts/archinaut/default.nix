{
  config,
  inputs,
  ...
}: let
  m = config.flake.modules;
in {
  configurations.nixos.archinaut.module = {
    modulesPath,
    lib,
    ...
  }: {
    imports = [
      # Kernel-direct boot: the base SD-image builder (NOT sd-image-aarch64.nix,
      # which hardcodes u-boot + extlinux) plus archinaut-kernel-direct, which
      # supplies a GPU-firmware-direct bootloader (no u-boot). This is what lets
      # the Pi boot with the printer powered — the Klipper MCU on the GPIO UART
      # used to hang u-boot's serial console. See
      # docs/implemented/2026-06-20-archinaut-kernel-direct-boot.md.
      (modulesPath + "/installer/sd-card/sd-image.nix")
      m.nixos.archinaut-kernel-direct
      inputs.sops-nix.nixosModules.sops
      m.nixos.profile-base
      m.nixos.profile-server
      m.nixos.archinaut-hardware
      m.nixos.klipper-host
      m.nixos.first-boot
      # Lite journal→Loki shipper (vector, ~30-60 MB) in place of alloy: alloy's
      # ~260 MB starved sshd during boot on this 1 GB Pi. vector gives the same
      # {source="journal",host=…} Loki stream at a Pi-tolerable footprint, so
      # archinaut stays visible in the fleet Logs dashboard.
      m.nixos.vector-logs
      # NOTE: btrfs-snapshots intentionally omitted — the SD root is ext4.
      # NOTE: alloy (full metrics+logs agent) omitted — too heavy; vector-logs
      # above ships journal logs only (host metrics not shipped from this Pi).
    ];

    # Rollback guard: the print stack must come back after an unattended upgrade.
    modules.upgradeHealthCheck.criticalUnits = [
      "sshd.service"
      "tailscaled.service"
      "klipper.service"
      "moonraker.service"
    ];

    system.stateVersion = "25.11";

    # Unattended upgrades — built on orion (aarch64 via binfmt), substituted here.
    system.autoUpgrade = {
      enable = true;
      flake = "git+https://github.com/ErikBPF/desktop-nixos?ref=main#archinaut";
      operation = "switch";
      flags = ["--show-trace"];
      allowReboot = false;
      # Weekly, not nightly: each switch writes a fresh system closure to the
      # microSD. Weekly cuts that write volume ~7x — meaningful SD-longevity on
      # a Pi (the 2026-07-07 card death was worn by a crash-loop + daily churn).
      dates = "Wed 05:00";
      # Stagger off the 05:00 herd so this 1 GB aarch64 Pi substitutes from a
      # settled orion cache (done by 04:30) instead of racing a busy builder.
      randomizedDelaySec = "900";
    };

    # 1 GB RPi3 trims: no SMART-capable disk (SD card), and the RPi kernel
    # rejects the auditd netlink rule-load — disable both to keep boot clean.
    services.smartd.enable = lib.mkForce false;
    security.auditd.enable = lib.mkForce false;
    security.audit.enable = lib.mkForce false;

    # Keep the journal persistent (auto would fall back to volatile if
    # /var/log/journal is missing on a fresh SD). On-card journal is what let us
    # diagnose the 2026-07-07 SD-death post-mortem; with the atuin/postgres
    # crash-loop gone (the real wear source), the capped journal (SystemMaxUse
    # =50M via logrotate.nix) writes little. vector-logs mirrors it to Loki so
    # logs survive even total card death.
    services.journald.storage = "persistent";

    # WiFi-only: blacklist the onboard USB ethernet (lan78xx). The C270 webcam
    # shares the Pi3's single dwc2 USB-2.0 bus with the NIC, and even an
    # idle/link-down lan78xx starved the camera's isochronous bandwidth —
    # continuous capture collapsed to 0fps within ~40s. With the NIC off the bus
    # (host is on WiFi now) the stream holds a steady ~24fps. Re-enable only if
    # reverting to wired. See modules/services/klipper-host.nix webcam block.
    boot.blacklistedKernelModules = ["lan78xx"];

    services.openssh.enable = true;
  };
}
