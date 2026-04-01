{config, ...}: let
  inherit (config) username;
  homeDir = "/home/${username}";
  composeDir = "${homeDir}/homelab";

  # Each entry becomes a systemd user service named podman-compose-<name>.
  # Order matters — infra (postgres, redis, vault, adguard) must come up before
  # anything that depends on them. networking (cloudflared, swag) before apps.
  stacks = [
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

  # Build a systemd user service for each stack.
  # - Wants/After network-online to ensure Tailscale is up before starting.
  # - Each stack After the previous one to enforce boot order.
  # - RemainAfterExit so systemd considers it active after compose up returns.
  makeService = idx: name: {
    "podman-compose-${name}" = {
      Unit = {
        Description = "Podman compose stack: ${name}";
        After =
          ["network-online.target"]
          ++ (
            if idx == 0
            then []
            else ["podman-compose-${builtins.elemAt stacks (idx - 1)}.service"]
          );
        Wants = ["network-online.target"];
      };
      Service = {
        Type = "oneshot";
        RemainAfterExit = true;
        WorkingDirectory = composeDir;
        ExecStart = "/run/current-system/sw/bin/docker compose -f ${composeDir}/${name}.yml up -d --remove-orphans";
        ExecStop = "/run/current-system/sw/bin/docker compose -f ${composeDir}/${name}.yml stop";
        # Give containers 60s to stop gracefully before systemd kills the service.
        TimeoutStopSec = 60;
      };
      Install.WantedBy = ["default.target"];
    };
  };
in {
  flake.modules.nixos.discovery-compose = {pkgs, ...}: {
    # Ensure docker-compose (podman compat) is available system-wide so the
    # ExecStart paths resolve correctly inside the user service environment.
    environment.systemPackages = [pkgs.docker-compose];

    home-manager.users.${username} = {
      systemd.user.services =
        builtins.foldl' (acc: item: acc // item) {}
        (builtins.genList (idx: makeService idx (builtins.elemAt stacks idx))
          (builtins.length stacks));
    };
  };
}
