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

    # EFI boot fix (root-caused via the OCI console-history API): after
    # nixos-infect, Oracle's UEFI still boots Ubuntu's NVRAM entry over the
    # removable-path GRUB that profile-oci-guest installs → the Ubuntu kernel
    # boots the NixOS root → getty/sshd (Nix binaries) can't run → host is dark
    # despite the network being up. Declarative fix: have NixOS manage its OWN
    # NVRAM entry (canTouchEfiVariables) so the NixOS GRUB entry wins, instead
    # of relying on the removable fallback Ubuntu's entry beats. Overrides
    # profile-oci-guest (efiInstallAsRemovable=true / canTouchEfiVariables=false)
    # for this host only; voyager predates the issue and keeps the profile's
    # defaults.
    boot.loader.grub.efiInstallAsRemovable = lib.mkForce false;
    boot.loader.efi.canTouchEfiVariables = lib.mkForce true;

    # Relay#2 identity for this host (RFC §4a/§R3/§R5): vanguard advertises
    # itself as relayHosts[1] (relay2.<zone>), not voyager's relay.<zone>. Only
    # takes effect once services.netbirdRelay.enable is flipped on — these are
    # just the option VALUES for when that happens.
    services.netbirdRelay.relayHostname = builtins.elemAt nb.relayHosts 1;
    # vanguard holds only an ephemeral public IP (unlike voyager's reserved
    # one) — see netbird-relay.nix's enableDdclient doc comment: this is a
    # documented placeholder value, not a wired ddclient config (that's a
    # TODO in netbird-relay.nix itself, not implemented here or there yet).
    services.netbirdRelay.enableDdclient = true;
  };
}
