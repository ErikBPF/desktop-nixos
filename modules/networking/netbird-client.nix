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

      # RFC §4b bootstrap fix: management (nb.<zone>) lives on discovery and
      # is only resolvable via discovery's own AdGuard — so a cold boot or a
      # discovery-down window can't resolve the name that points at the host
      # that's supposed to serve it. Ship a static hosts entry pointing the
      # management hostname straight at discovery's tailnet IP as a
      # resolver-independent floor; DNS stays authoritative for everything
      # else (and for the eventual DR-flip mobility, §4a).
      networking.hosts.${fleet.hosts.discovery.tailscaleIp} = [managementHost];

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
        login.systemdDependencies = ["sops-nix.service"];
      };
    };
  };
}
