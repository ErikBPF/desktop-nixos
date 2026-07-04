{
  config,
  inputs,
  ...
}: let
  m = config.flake.modules;
in {
  configurations.nixos.discovery.module = {
    pkgs,
    modulesPath,
    ...
  }: {
    imports = [
      (modulesPath + "/installer/scan/not-detected.nix")
      inputs.disko.nixosModules.disko
      inputs.sops-nix.nixosModules.sops
      m.nixos.profile-base
      m.nixos.profile-server
      m.nixos.systemd-boot-counting
      m.nixos.discovery-hardware
      m.nixos.discovery-networking
      m.nixos.discovery-diagnostics
      m.nixos.discovery-syncthing
      m.nixos.discovery-haos
      m.nixos.first-boot
      m.nixos.alloy
      m.nixos.kepler-nfs
      m.nixos.discovery-containers
      m.nixos.discovery-compose
      m.nixos.discovery-harbor
      m.nixos.discovery-restic-voyager-check
      m.nixos.discovery-telstar-capture
      # OCI cutover (2026-06-25): replace the live servarr Docker hermes with
      # the declarative hermes-flake OCI module (official image + Nix-rendered
      # config/SOUL/sops, rtk store-mounted, git-versioned skills via
      # external_dirs). Keeps the `hermes-agent` name + ports + homelab-net so
      # SWAG/litellm wiring is unchanged. The old nspawn blueprint
      # (./hermes-agent.nix, module discovery-hermes-agent) is superseded and no
      # longer imported. ⚠ Cutover is NOT live until the servarr hermes stack is
      # stopped and the sops env gains bare TELEGRAM_BOT_TOKEN/DISCORD_BOT_TOKEN
      # — see docs/implemented/2026-06-24-hermes-memory-skills.md §8 runbook.
      m.nixos.discovery-hermes-oci
      # Declarative bootstrap for the hermes native LLM wiki (sops deploy key +
      # vault.git@hermes clone oneshot + daily wiki-consolidate cron seed) so the
      # wiki survives a reprovision. See docs/hermes-llm-wiki.md.
      m.nixos.discovery-hermes-wiki
      m.nixos.power-desktop
      m.nixos.btrfs-snapshots
      m.nixos.homelab-iac-drift
      m.nixos.restic-tofu-state
      m.nixos.swag-cert-monitor
      m.nixos.discovery-vault
    ];

    # Discord webhook for incident alerts (cert monitor, restic failure, iac
    # drift) now comes from OpenBao via vault-agent (P3.2) — rendered to
    # /run/vault-agent/discord_webhook_incidents, not sops. Vault is the
    # runtime-secret SSOT; the sops copy was removed to de-dup. Alerts go to
    # Discord (off-host) so a SWAG/ingress outage can't silence them.

    # Liveness probe for the SWAG ingress cert. The 2026-06-29 outage was silent
    # (cert failed to mint, every subdomain 000) — this alerts on a dead :443
    # handshake, a non-LE (self-signed fallback) cert, or near-expiry before a
    # user hits a dead subdomain. Canary subdomain rides the *.homelab wildcard.
    services.swagCertMonitor = {
      enable = true;
      host = "kindle.homelab.pastelariadev.com";
      discordWebhookFile = "/run/vault-agent/discord_webhook_incidents";
    };

    # Versioned backup of the tofu-state mirror onto vault (sdb), independent of
    # the primary SSD that holds the live state. Off-host copies go to orion +
    # kepler via Syncthing (discovery-syncthing tofu-state folder). The SFTP
    # peer copy (kepler) and the REST copy (voyager) are the off-machine tiers;
    # only voyager is off-premise (Oracle), the append-only escape from a
    # whole-house loss.
    services.resticTofuState = {
      enable = true;
      healthcheck = true;
      discordWebhookFile = "/run/vault-agent/discord_webhook_incidents";
      offsiteRepository = "sftp:restic-kepler:/bulk/backups/restic-offsite/tofu-state";
      restRepository = true;
    };

    # Drift detection for the homelab-iac repo (UniFi/Tailscale/Cloudflare/
    # AdGuard). Runs here because discovery is the 24/7 host with LAN + tailnet
    # reach to every provider and hosts the MinIO state backend it plans against.
    services.homelabIacDrift = {
      enable = true;
      repoPath = "/home/${config.username}/homelab-iac";
      user = config.username;
      discordWebhookFile = "/run/vault-agent/discord_webhook_incidents";
    };

    # Rollback guard: docker runs the compose stacks, libvirtd runs HAOS.
    modules.upgradeHealthCheck.criticalUnits = [
      "sshd.service"
      "tailscaled.service"
      "docker.service"
      "libvirtd.service"
    ];

    # NOTE: fuse-overlayfs storage.conf removed — discovery now uses rootful
    # Docker instead of rootless Podman. See modules/hosts/discovery/containers.nix.
    home-manager.users.${config.username}.imports = [
      m.home.discovery-ssh
    ];

    # Lingering allows erik's systemd user session (and user services) to
    # survive after logout and start on boot without an interactive login.
    # Required for rootless Podman compose stacks to auto-start.
    users.users.${config.username}.linger = true;

    system.stateVersion = "25.11";
    nixpkgs.hostPlatform = "x86_64-linux";
    hardware.cpu.intel.updateMicrocode = true;

    # Bootloader: systemd-boot + boot-counting via the systemd-boot-counting
    # module imported above (grub off, panic=10). Migrated GRUB → systemd-boot
    # 2026-07-03. /boot is the vfat ESP; cap at ~2 generations for the 512M ESP.
    boot.loader.efi.canTouchEfiVariables = true;
    boot.loader.systemd-boot.configurationLimit = 2;

    boot.kernel.sysctl."net.ipv4.ip_unprivileged_port_start" = 53;

    hardware.nvidia-container-toolkit.enable = true;

    system.autoUpgrade = {
      enable = true;
      flake = "github:ErikBPF/desktop-nixos#discovery";
      # boot + in-window reboot: avoids a live nvidia/kernel-bump driver mismatch.
      # discovery runs OpenBao — a reboot seals it, but boot auto-unseal recovers
      # (see openbao seal-probe). randomizedDelaySec staggers off the orion cache.
      operation = "boot";
      flags = ["--show-trace"];
      allowReboot = true;
      dates = "05:00";
      randomizedDelaySec = "900";
      rebootWindow = {
        lower = "05:00";
        upper = "06:00";
      };
    };
  };
}
