{ config, lib, pkgs, ... }:

{
  environment.systemPackages = [
    pkgs.jellyfin
    pkgs.jellyfin-web
    pkgs.jellyfin-ffmpeg
  ];

  nixpkgs.config.packageOverrides = pkgs: {
    vaapiIntel = pkgs.vaapiIntel.override { enableHybridCodec = true; };
  };
  hardware.opengl = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver
      vaapiIntel
      vaapiVdpau
      libvdpau-va-gl
      intel-compute-runtime
    ];
  };

  services.jellyfin = {
    enable = true;
    openFirewall = true;
  };

  services.searx = {
    enable = true;
    settings = {
      server = {
        port = 8888;
        bind_address = "127.0.0.1";
        secret_key = "secret key";
      };
    };
  };

  #services.nextcloud = {
    #enable = true;
   # database.createLocally = true;
   # configureRedis = true;
   # https = true;
   # package = pkgs.nextcloud28;
   # hostName = "next.bednarek.cloud";
   # config = {
   #   adminuser = "erik";
   #   adminpassFile = "/run/secrets/misc/nextcloud";
   # };
  #};

  services.nginx = {
    enable = true;
    # any extra configuration here
    virtualHosts = {
      "search.bednarek.cloud" = {
        # this can be anything, being an arbitrary identifier
        forceSSL = true;
        enableACME = true;
        serverName = "search.bednarek.cloud"; # replace this with whatever you're serving from
        # SearX proxy
        locations."/" = {
          proxyPass = "http://${toString config.services.searx.settings.server.bind_address}:${toString config.services.searx.settings.server.port}";
          proxyWebsockets = true;
          recommendedProxySettings = true;
        };
      };
  #    "next.bednarek.cloud" = {
  #      # this can be anything, being an arbitrary identifier
  #      forceSSL = true;
  #      enableACME = true;
  #    };
    };
  };

  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = true;
  };

  services.rsnapshot = {
    enable = true;
    enableManualRsnapshot = false;
    extraConfig = ''
snapshot_root	/mnt/backups/
retain	hourly	24
retain	daily	7
backup	/home/erik/Camera	localhost/
backup	/home/erik/Documents	localhost/
backup	/home/erik/Code	localhost/
      '';
    cronIntervals = {
        daily = "0 0 * * *";
        hourly = "0 * * * *";
    };
  };

  networking.firewall.allowedTCPPorts = [ 80 443 8096 8384 ];
  systemd.services.NetworkManager-wait-online.enable = lib.mkForce true;
  environment.persistence."/persist" = {
    directories = [
      "/mnt"
  #    "/var/lib/nextcloud"
      "/var/lib/redis-nextcloud"
      "/var/lib/acme"
      "/var/lib/jellyfin"
      "/var/cache/jellyfin"
      "/run/acme"
  #    "/run/redis-nextcloud"
      "/run/nginx"
      "/run/searx"
    ];
  };
}
