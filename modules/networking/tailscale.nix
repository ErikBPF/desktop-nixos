{self, ...}: {
  flake.modules.nixos.tailscale = {config, ...}: {
    sops.age.keyFile = "/home/erik/.config/sops/age/keys.txt";

    sops.secrets."tailscale_authkey" = {
      sopsFile = self + "/secrets/sops/secrets.yaml";
    };

    services.tailscale = {
      enable = true;
      openFirewall = true;
      useRoutingFeatures = "client";
      authKeyFile = config.sops.secrets."tailscale_authkey".path;
      extraUpFlags = [
        "--accept-dns=true"
        "--accept-routes"
        "--hostname=${config.networking.hostName}"
      ];
    };
  };
}
