_: {
  flake.modules.nixos.discovery-compose = _: {
    homelab.compose = {
      composeDir = "/home/erik/servarr/machines/discovery";
      # Rootful Docker — socket owned by root, accessible via docker group.
      dockerSocket = "unix:///run/docker.sock";
      stacks = [
        # shared.yml has no services on discovery (alloy/syncthing/etc run natively)
        "infra" # postgres, redis, vault, adguard
        "networking" # cloudflared, swag
        "monitoring" # grafana, loki, prometheus, scrutiny
        "plex" # plex (host network)
        "media-server" # jellyfin, tautulli, jellystat
        "media" # sonarr, radarr, lidarr, gluetun, etc.
        "tools" # litellm, langfuse, obsidian, excalidraw, it-tools, etc.
        "homepage" # homepage dashboard
        "tunneling" # cloudflare tunnels
        "ai-serving" # ai inference stack
        "dockhand" # dockhand container updater
      ];
    };
  };
}
