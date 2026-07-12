{
  self,
  config,
  ...
}: let
  fleet = config.flake.fleet;
in {
  flake.modules.nixos.netbird-client = {
    config,
    lib,
    ...
  }: let
    cfg = config.modules.networking.netbird-client;
    # Bare hostname netbird enrols against — fleet.netbird.managementUrl is
    # always a plain "https://<host>" value (no port/path), see meta.nix.
    managementHost = lib.removePrefix "https://" fleet.netbird.managementUrl;
  in {
    # Opt-in, disabled by default (RFC §1/WP1 guard rail): importing this
    # module does nothing until a host flips this on.
    options.modules.networking.netbird-client.enable =
      lib.mkEnableOption "NetBird self-hosted overlay client (docs/proposals/2026-07-10-netbird-selfhosted-overlay.md)";

    config = lib.mkIf cfg.enable {
      # Setup-key login secret. Real value is minted by a human (Phase S) —
      # this only declares where sops-nix should look for it.
      sops.secrets."netbird/setup_key" = {
        sopsFile = self + "/secrets/sops/secrets.yaml";
        mode = "0400";
      };

      services.resolved.enable = true;

      # RFC §4b bootstrap fix: management (nb.<zone>) lives on discovery and is
      # only resolvable via discovery's own AdGuard — so a cold boot or a
      # discovery-down window can't resolve the name. Ship a static hosts entry
      # as a resolver-independent floor. Point it at discovery's LAN IP, NOT its
      # tailscale IP: the control plane is served by SWAG on :443, and the
      # tailscale ACL only grants *.homelab :443 via the `swag` host (discovery's
      # LAN IP 192.168.10.210, homelab-iac tailscale/acl rule 3) — discovery's
      # tailscale IP :443 has NO ACL rule, so a tailscale-IP floor is blocked and
      # `netbird up` times out. On-LAN peers reach the LAN IP directly; off-LAN
      # peers via discovery's advertised subnet route (accept-routes). DNS stays
      # authoritative for everything else (and for DR-flip mobility, §4a).
      networking.hosts.${fleet.hosts.discovery.ip} = [managementHost];

      services.netbird.clients.netbird = {
        port = 51820;
        # Management URL is wired via NB_MANAGEMENT_URL (netbird's CLI binds
        # every persistent flag to an NB_<FLAG> env var — see
        # client/cmd/root.go SetFlagsFromEnvVars/FlagNameToEnvVar, confirmed
        # against the pinned nixpkgs netbird 0.74.2), not the module's
        # experimental `config` JSON-override — ManagementURL round-trips
        # config.json as a nested url.URL object, not a plain string, so a
        # naive string override would fail to unmarshal on daemon start.
        environment.NB_MANAGEMENT_URL = fleet.netbird.managementUrl;
        login.enable = true;
        login.setupKeyFile = config.sops.secrets."netbird/setup_key".path;
        # login.systemdDependencies is intentionally left at its default []: this
        # fleet has no `sops-nix.service`/`sops-install-secrets.service` unit
        # (system secrets are decrypted in the activation script, before any unit
        # starts), so there is nothing to order against — /run/secrets/netbird/
        # setup_key is already present when netbird-login's LoadCredential reads
        # it. Do NOT add `["sops-nix.service"]` back: it made the unit
        # unstartable ("Unit sops-nix.service not found").
      };
    };
  };
}
