{
  self,
  config,
  ...
}: let
  fleet = config.flake.fleet;
in {
  flake.modules.nixos.tailscale = {
    config,
    lib,
    ...
  }: let
    # Fleet-wide OAuth enrollment: hosts authenticate with a non-expiring OAuth
    # client secret (sops tailscale_authkey, scope auth_keys / tag:server,
    # ephemeral=false) instead of a 90-day auth key that expires and breaks
    # tailscaled-autoconnect. OAuth-minted keys REQUIRE the node to advertise a
    # tag the client owns — but only *servers* should be tagged tag:server, not
    # the admin workstation or roaming laptop. Selected by the fleet role SSOT
    # (meta.nix), so orion (server on the desktop profile) is included and
    # pathfinder/laptop are not. tag:server ownership lives in homelab-iac
    # tailscale/acl/policy.hujson. Existing user-owned nodes keep working; this
    # applies on their next (re-)enrollment.
    role = fleet.hosts.${config.networking.hostName}.role or null;
  in {
    sops.secrets."tailscale_authkey" = {
      sopsFile = self + "/secrets/sops/secrets.yaml";
    };

    services.tailscale = {
      enable = true;
      openFirewall = true;
      useRoutingFeatures = "client";
      authKeyFile = config.sops.secrets."tailscale_authkey".path;
      extraUpFlags =
        [
          "--accept-dns=true"
          "--accept-routes"
          "--hostname=${config.networking.hostName}"
        ]
        ++ lib.optional (role == "server") "--advertise-tags=tag:server";
    };
  };
}
