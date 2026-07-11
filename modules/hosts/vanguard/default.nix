{
  config,
  inputs,
  ...
}: let
  m = config.flake.modules;
  nb = config.flake.fleet.netbird; # relayHosts[1] = relay2.<zone>, this host's relay
in {
  configurations.nixos.vanguard.module = {
    lib,
    modulesPath,
    ...
  }: {
    imports = [
      (modulesPath + "/installer/scan/not-detected.nix")
      inputs.sops-nix.nixosModules.sops
      m.nixos.profile-base
      m.nixos.profile-server
      m.nixos.profile-oci-guest
      m.nixos.vanguard-hardware
      m.nixos.vanguard-networking
      m.nixos.containers
      m.nixos.node-exporter
      m.nixos.first-boot
      # Role modules (docs/proposals/2026-07-10-vanguard-second-oracle-node.md).
      # ALL opt-in/disabled by default — importing only registers the options,
      # nothing activates until a role's own `enable` is flipped on. Enable in
      # phases per the proposal (R1+R2 first, R3 next, R4 last and only after
      # its extra prerequisites are met).
      m.nixos.fleet-dns # R1
      m.nixos.dead-mans-switch # R2
      m.nixos.pg-replica # R3 (NetBird DB read-replica)
      m.nixos.vault-witness # R4 — see the heavy warning in that file
      # NetBird relay#2 (R3/R5): reuse the SAME deferredModule voyager uses
      # (modules/hosts/voyager/netbird-relay.nix) — only the option values
      # below differ per host. Registers services.netbirdRelay but stays
      # disabled here too (services.netbirdRelay.enable defaults false).
      m.nixos.netbird-relay
    ];

    # Rollback guard: a public-facing host must keep SSH + Tailscale up.
    modules.upgradeHealthCheck.criticalUnits = [
      "sshd.service"
      "tailscaled.service"
    ];

    system.stateVersion = "25.11";
    # Oracle Always-Free x86 shape (VM.Standard.E2.1.Micro, 1 GB) — the second
    # AMD micro, sibling of voyager. A1 (aarch64) capacity is scarce in
    # sa-saopaulo-1 (see telstar), so vanguard is the provisionable-now sibling
    # on the x86 micro, same as voyager. The 1 GB micro can't kexec-install
    # (OOMs), so it is provisioned via nixos-infect on a stock Ubuntu cloud
    # image (same path as voyager).
    nixpkgs.hostPlatform = "x86_64-linux";

    # Oracle VM is ~1GB RAM. zram is intentionally disabled on this host; keep
    # /tmp off tmpfs so activation does not consume scarce RAM.
    zramSwap.enable = false;
    boot.tmp.useTmpfs = lib.mkForce false;
    boot.tmp.cleanOnBoot = true;

    # Oracle block volumes don't support SMART; smartd exits non-zero and
    # marks the system degraded. Disable it on this guest.
    services.smartd.enable = lib.mkForce false;

    # Phase 1 roles (docs/proposals/2026-07-10-vanguard-second-oracle-node.md
    # §enablement): the light pair — R1 CoreDNS secondary resolver (tailnet
    # fallback, tens of MB, bound to tailscale0) + R2 offsite dead-man's-switch
    # prober (a plain systemd timer). Both cheap on the 1 GB box; R3/R4 stay off
    # until later phases.
    services.fleetDns.enable = true;
    services.deadMansSwitch.enable = true;
    # The role's default checkUrl is the ingress apex, which SWAG has no cert
    # for (curl --fail would fail every probe → false alarms). Probe PocketID
    # instead: SWAG-fronted on discovery (the ingress host), public, always-on,
    # returns 200 — the closest single "home ingress reachable" signal.
    services.deadMansSwitch.checkUrl = "https://id.${config.flake.fleet.ingress.homelab.zone}";

    # EFI boot: keep profile-oci-guest's removable-fallback path
    # (efiInstallAsRemovable=true / canTouchEfiVariables=false), the
    # voyager-proven route. A declarative NVRAM entry does NOT survive Oracle's
    # stop/start (OCI drops EFI vars — see the profile comment), so the fix for
    # Ubuntu's leftover entry winning is imperative and lives in the infect step:
    # `just infect-vanguard` deletes Ubuntu's `ubuntu` NVRAM entry + its
    # `/boot/efi/EFI/ubuntu` dir during the noreboot window so firmware falls
    # back to NixOS's removable BOOT<arch>.EFI. Nothing host-specific to override
    # here.

    # DIAGNOSTIC (2026-07-11): make GRUB itself emit to the Oracle serial console
    # (ttyS0). NixOS GRUB defaults to gfxterm on the VGA tty0, so a GRUB-level
    # hang/rescue is invisible on the OCI serial console (which only shows the
    # firmware POST, then goes dark the instant GRUB takes over — exactly what we
    # observed). The kernel already logs to ttyS0 via profile-oci-guest's
    # console=; this extends that to the bootloader so we can watch the menu and
    # any error. Harmless if it boots fine.
    boot.loader.grub.extraConfig = ''
      serial --unit=0 --speed=115200 --word=8 --parity=no --stop=1
      terminal_input console serial
      terminal_output console serial
    '';

    # Relay#2 (R3a — enabled): vanguard advertises itself as relayHosts[1]
    # (relay2.<zone>), a distinct public relay from voyager's relay.<zone>. Its
    # public :443 (WSS/QUIC) is opened on the shared Oracle security list
    # (homelab-iac oracle/compute relay_public_surface=true); the relay's
    # built-in Let's-Encrypt client obtains the cert for relay2.<zone>.
    # NB_AUTH_SECRET (sops netbird/auth_secret) is byte-identical to discovery's
    # management (§6b-H7) — decryptable here via the shared primary age key.
    services.netbirdRelay.enable = true;
    services.netbirdRelay.relayHostname = builtins.elemAt nb.relayHosts 1;
    # DNS: relay2.<zone> is a STATIC A record at vanguard's ephemeral IP, managed
    # in homelab-iac (cloudflare/dns), bumped on reprovision — so no on-host
    # ddclient/Cloudflare-token is needed. Keep the module's ddclient path off.
    services.netbirdRelay.enableDdclient = false;
  };
}
