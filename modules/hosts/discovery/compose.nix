_: {
  flake.modules.nixos.discovery-compose = _: {
    homelab.compose = {
      composeDir = "/home/erik/servarr/machines/discovery";
      # Rootful Docker — socket owned by root, accessible via docker group.
      dockerSocket = "unix:///run/docker.sock";
      # P3.3: these stacks' secrets come from OpenBao via vault-agent — compose
      # gets a second --env-file /run/vault-agent/<stack>.env (see orchestration.nix).
      vaultEnvStacks = {
        tunneling = ["tunneling"];
        monitoring = ["monitoring" "shared-grafana"];
        tools = ["tools"];
        media = ["media" "shared-arr"];
        networking = ["networking"];
        homepage = ["shared-arr" "shared-grafana"];
        "media-server" = ["media-server" "shared-db"];
        "ai-serving" = ["ai-serving" "shared-db"];
        "ha-harness" = ["ha-harness"];
        infra = ["shared-db"];
      };
      secretSpecRuntimeProfiles.tools = "tools";
      secretSpecRuntimeHealthContainers.tools = "searxng";
      secretSpecRuntimeProfiles.ha-harness = "ha-harness";
      secretSpecRuntimeHealthContainers.ha-harness = "ha-harness";
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
        "ha-harness" # HA Qwen tool-caller dry-run; no HA dispatch credential
        "dockhand" # dockhand container updater
        "firmware" # static OTA firmware host (cosmo-notes), LAN-only via SWAG
        "kindle-dash" # e-ink dashboard renderer
      ];
    };
  };
}
