{self, ...}: {
  flake.modules.nixos.nix-cache = {
    config,
    pkgs,
    lib,
    ...
  }: {
    # nix-serve signs and serves the local nix store over plain HTTP.
    # Binds on all interfaces (0.0.0.0) at port 5000 so the cache is reachable
    # both on the LAN (http://192.168.10.220:5000) and over Tailscale, where
    # clients reach it by MagicDNS short name (http://orion:5000). A single
    # hardcoded LAN IP left the Tailscale interface unserved and broke the bind
    # at boot when DHCP was slow.
    # No TLS for now (DNS lives on Discovery which may be offline).
    # The signing private key is managed by sops-nix.
    sops.secrets.nix_cache_signing_key = {
      sopsFile = self + "/secrets/sops/secrets.yaml";
      mode = "0400";
    };

    services.nix-serve = {
      enable = true;
      bindAddress = "0.0.0.0";
      port = 5000;
      secretKeyFile = config.sops.secrets.nix_cache_signing_key.path;
    };

    networking.firewall.allowedTCPPorts = [5000];

    # Daily closure builder — keeps the cache warm by building all host closures.
    # Runs at 03:00, requires the flake repo to be checked out at the path below.
    systemd.services.nix-cache-builder = {
      description = "Build all host closures to warm the nix cache";
      # Never let activation queue a job for this oneshot: a deploy landing
      # while the warm is running would block switch-to-configuration until
      # all five closures finish (observed: 40 min hang, 2026-06-10).
      restartIfChanged = false;
      stopIfChanged = false;
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        WorkingDirectory = "/var/lib/nix-cache-builder/repo";
      };
      path = [pkgs.git pkgs.nix];
      script = ''
        set -euo pipefail
        echo ":: Syncing repo to origin/main..."
        git fetch --prune origin
        git reset --hard origin/main

        echo ":: Building host closures..."
        nix build .#nixosConfigurations.orion.config.system.build.toplevel --no-link
        nix build .#nixosConfigurations.pathfinder.config.system.build.toplevel --no-link
        nix build .#nixosConfigurations.laptop.config.system.build.toplevel --no-link
        nix build .#nixosConfigurations.discovery.config.system.build.toplevel --no-link
        nix build .#nixosConfigurations.kepler.config.system.build.toplevel --no-link

        echo ":: Cache builder complete"
      '';
    };

    systemd.timers.nix-cache-builder = {
      description = "Daily nix cache builder timer";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnCalendar = "03:00";
        Persistent = true;
      };
    };
  };
}
