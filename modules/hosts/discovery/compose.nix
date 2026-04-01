_: {
  flake.modules.nixos.discovery-compose = _: {
    homelab.compose.stacks = [
      "shared" # homelab-net network creation — must be first
      "infra" # postgres, redis, vault, adguard
      "networking" # cloudflared, swag
      "monitoring" # grafana, loki, prometheus, scrutiny
      "plex" # plex (host network)
      "media-server" # jellyfin, tautulli, jellystat
      "media" # sonarr, radarr, lidarr, etc.
      "tools" # litellm, langfuse, obsidian, excalidraw, it-tools, etc.
      "homepage" # homepage dashboard
      "tunneling" # anything tunnel-related
      "ai-serving" # ai inference stack
      "dockhand" # dockhand container updater
    ];
  };
}
