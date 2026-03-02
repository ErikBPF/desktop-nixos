{ config, ... }:
{
  # sops.secrets."tailscale_authkey" = {
  #   sopsFile = ../../../secrets/sops/secrets.yaml;
  # };

  services.tailscale = {
    enable = true;
    openFirewall = true;
    # authKeyFile = config.sops.secrets."tailscale_authkey".path;
    # extraUpFlags = [
    #   "--accept-dns=true"
    #   "--hostname=${config.networking.hostName}"
    # ];
  };
}
