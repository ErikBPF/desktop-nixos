# NetBird native relay — WP3 of the NetBird implementation plan.
# Reusable deferredModule: the SAME module also covers the Track-1 2nd VM
# (§4a) once it's provisioned; only the option *values* differ per host.
#
#   plan:   docs/proposals/2026-07-10-netbird-implementation-plan.md (WP3)
#   design: docs/proposals/2026-07-10-netbird-selfhosted-overlay.md
#           §4a (2nd VM), §5 (exposure), §6b (voyager hardening, full),
#           §9 (secrets); rulings §11 Q3/Q4/Q8/Q9/Q10
#
# L2/§5: this relay's :443 is the ONLY public surface in the whole NetBird
# design. §6b turns that into a checklist — H1 (no self-hosted STUN), H2
# (Oracle SL, WP4/homelab-iac, not here), H3 (nftables rate-limits, TODO
# below), H4 (metrics/health tailnet-only), H5 (cgroup caps), H6 (egress
# watchdog, WP4/monitoring, not here), H7 (secret hygiene).
#
# DISABLED BY DEFAULT (services.netbirdRelay.enable = false). Everything below
# sits under `lib.mkIf cfg.enable`, so `just dry voyager` stays a clean no-op
# even though this module is imported by voyager/default.nix and its sops
# secret is a placeholder that doesn't exist in secrets/sops/secrets.yaml yet
# (Phase S, human-gated — see the implementation plan).
{
  config,
  self,
  ...
}: let
  inherit (config) username email;
  nb = config.flake.fleet.netbird; # managementUrl, overlayCidr, dnsDomain, relayHosts
in {
  flake.modules.nixos.netbird-relay = {
    config,
    lib,
    ...
  }: let
    cfg = config.services.netbirdRelay;
    sopsFile = self + "/secrets/sops/secrets.yaml";
  in {
    options.services.netbirdRelay = {
      enable = lib.mkEnableOption "the NetBird native relay (rootless podman oci-container) — disabled by default, see the NetBird RFC (Phase S/O are human-gated)";

      image = lib.mkOption {
        type = lib.types.singleLineStr;
        default = "docker.io/netbirdio/relay:0.74.3"; # TODO(Phase-O): mirror through Harbor + pin digest (§8 supply-chain note)
        description = "netbirdio/relay image (multi-arch amd64/arm64).";
      };

      relayHostname = lib.mkOption {
        type = lib.types.singleLineStr;
        default = builtins.head nb.relayHosts;
        description = ''
          Public FQDN this relay instance serves — the relay advertises
          itself as `rels://<relayHostname>:443` and requests its
          Let's-Encrypt cert for it. Voyager (this default) is
          `relayHosts[0]`; the Track-1 2nd VM (§4a) overrides this to
          `elemAt nb.relayHosts 1` in its own host config.
        '';
      };

      publicInterface = lib.mkOption {
        type = lib.types.singleLineStr;
        default = "ens3";
        description = "Public NIC name; the firewall opens 443/tcp+udp here only. Override on a host with a different interface name.";
      };

      letsEncryptEmail = lib.mkOption {
        type = lib.types.singleLineStr;
        default = email;
        description = "Registration email for the relay's built-in Let's Encrypt client (Q3).";
      };

      memoryLimit = lib.mkOption {
        type = lib.types.singleLineStr;
        default = "128m";
        description = "podman --memory cap (§6b-H5).";
      };

      cpuLimit = lib.mkOption {
        type = lib.types.singleLineStr;
        default = "0.5";
        description = "podman --cpus cap (§6b-H5).";
      };

      pidsLimit = lib.mkOption {
        type = lib.types.int;
        default = 100;
        description = "podman --pids-limit cap (§6b-H5).";
      };

      enableDdclient = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          TODO(Track-1 2nd VM, RFC §4a): the second relay VM holds only an
          ephemeral Oracle public IP (voyager's reserved IP is a one-per-
          tenancy Always-Free perk), so that host additionally needs
          `services.ddclient` (protocol = "cloudflare") to keep
          `relayHostname`'s A record pointed at its current IP. NOT wired
          here — this option is a documented placeholder; implement the
          ddclient config on the 2nd VM's own host module when it is
          actually provisioned. Voyager (this instance) holds a reserved
          IP and needs no DDNS, so this must stay false here.
        '';
      };
    };

    config = lib.mkIf cfg.enable {
      # Matches WP2's explicit backend pin on discovery: voyager already runs
      # rootless podman (modules/virtualization/containers.nix), and
      # oci-containers defaults to "podman" on stateVersion >= 22.05 anyway,
      # but pin it explicitly rather than lean on that inference.
      virtualisation.oci-containers.backend = "podman";

      # Rootless podman binding the container's published :443 to the host
      # needs the low-port grant — same mechanism already used on discovery
      # for AdGuard's :53 (modules/hosts/discovery/default.nix). Scoped to
      # 443 exactly (tighter than discovery's 53) since nothing else on
      # voyager needs a privileged port.
      boot.kernel.sysctl."net.ipv4.ip_unprivileged_port_start" = 443;

      # oci-containers' rootless (podman.user != root) wiring wants lingering
      # for the user so the container survives logout/reboot without an
      # interactive login. Voyager already gets this transitively via
      # homelab.compose (voyager-compose.nix's non-empty `stacks`), but that's
      # an indirect dependency the 2nd VM reuse might not share — set it
      # explicitly here so this module is self-contained.
      users.users.${username}.linger = true;

      # H7: NB_AUTH_SECRET must be byte-identical across management and every
      # relay (mismatch fails silently) — same secret WP2 already declares on
      # discovery (modules/hosts/discovery/netbird-server.nix). One value in
      # secrets/sops/secrets.yaml, read by both hosts.
      # TODO(Phase-S, RFC §11-Q4/§14): today `secrets/sops/secrets.yaml` is
      # only encrypted to the shared `primary`/orion/archinaut age keys —
      # voyager's `.sops.yaml` anchor is still a placeholder
      # (age1PLACEHOLDER_REPLACE_ME_voyager_phase_s). Before this can
      # actually decrypt anything, a human must: generate voyager's own
      # age key on-host, replace the placeholder, add it to this file's
      # key_groups, and re-encrypt — never copy the shared `primary` private
      # key onto this internet-facing box (that's the whole point of Q4).
      sops.secrets."netbird/auth_secret" = {
        inherit sopsFile;
        format = "yaml";
        key = "netbird/auth_secret";
        mode = "0400";
        owner = username; # the podman-netbird-relay unit runs as this user (rootless), not root
        path = "/run/secrets/netbird-auth-secret";
        restartUnits = ["podman-netbird-relay.service"];
      };

      virtualisation.oci-containers.containers.netbird-relay = {
        inherit (cfg) image;
        podman.user = username;
        environment = {
          NB_LISTEN_ADDRESS = ":443";
          NB_EXPOSED_ADDRESS = "rels://${cfg.relayHostname}:443";
          NB_LETSENCRYPT_DOMAINS = cfg.relayHostname;
          NB_LETSENCRYPT_EMAIL = cfg.letsEncryptEmail;
          NB_LETSENCRYPT_DATA_DIR = "/data";
          NB_METRICS_PORT = "9090";
          NB_HEALTH_LISTEN_ADDRESS = "0.0.0.0:9000"; # exposure controlled by firewall (§6b-H4), not bind address
          # NB_ENABLE_STUN intentionally left unset (defaults false) — Q9/
          # §6b-H1: no self-hosted STUN reflector, ever, on any relay in this
          # design. External STUN is listed in management's Stuns: (WP2).
          # pprof: no flag/env below ever enables it (§6b-H4) — off by construction.
        };
        environmentFiles = [config.sops.secrets."netbird/auth_secret".path];
        volumes = ["/var/lib/netbird-relay/letsencrypt:/data"];
        ports = [
          "443:443"
          "443:443/udp"
          "9090:9090" # metrics — tailnet-only via firewall below, never on publicInterface
          "9000:9000" # health — same scoping
        ];
        # §6b-H5 cgroup caps: a flood or bug on the public relay can't starve
        # the DR-anchor's restic receiver sharing this box.
        extraOptions = [
          "--memory=${cfg.memoryLimit}"
          "--cpus=${cfg.cpuLimit}"
          "--pids-limit=${toString cfg.pidsLimit}"
        ];
      };

      systemd.tmpfiles.rules = ["d /var/lib/netbird-relay/letsencrypt 0700 ${username} users - -"];

      # §6b-H2/H4: 443 is the only public port, opened on the public NIC only
      # (matches voyager-networking.nix's per-interface style, which scopes
      # restic's :8000 to tailscale0 the same way). Metrics/health are NOT
      # added to any public-interface allow-list — they only reach the
      # tailnet, and STUN's :3478 is never opened anywhere (H1/Q9).
      networking.firewall.interfaces.${cfg.publicInterface} = {
        allowedTCPPorts = [443];
        allowedUDPPorts = [443];
      };
      networking.firewall.interfaces.tailscale0.allowedTCPPorts = [9090 9000];

      # TODO(§6b-H3, deliberately NOT implemented in this work package): host
      # nftables default-deny + per-source connection-rate limiting on :443
      # (a dynamic meter/named set with `limit rate`), a global SYN/UDP rate
      # cap with burst, and a conntrack table-size cap + shorter UDP timeout.
      # The relay rejects tokenless clients cheaply but only AFTER the
      # TLS/QUIC handshake, so a handshake flood still burns the single core
      # first — that's what these rules would mitigate. The PRIMARY L3 gate
      # is the Oracle security-list (WP4/homelab-iac `oracle/modules/instance`
      # — 443/tcp+udp only, written but not applied — RFC §6b-H2); nftables
      # here is defense-in-depth on top of it. Skipped now because a correct
      # rate-limit ruleset needs tuning against real traffic (nothing to
      # tune against pre-deploy); revisit once this relay is actually live
      # (RFC §10 phase 3) and real connection rates can inform the limits.
    };
  };
}
