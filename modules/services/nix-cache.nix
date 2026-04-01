{self, ...}: {
  flake.modules.nixos.nix-cache = {
    config,
    pkgs,
    lib,
    ...
  }: {
    # nix-serve signs and serves the local nix store over plain HTTP.
    # Binds on all interfaces at port 5000 — reachable at http://192.168.10.220:5000
    # on the LAN. No TLS for now (DNS lives on Discovery which may be offline).
    # The signing private key is managed by sops-nix.
    sops.secrets.nix_cache_signing_key = {
      sopsFile = self + "/secrets/sops/secrets.yaml";
      # nix-serve runs as a DynamicUser (no persistent system account).
      # World-readable is acceptable here: the key signs LAN-internal store
      # paths; anyone on the machine can already read the nix store.
      mode = "0444";
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
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        WorkingDirectory = "/var/lib/nix-cache-builder/repo";
      };
      path = [pkgs.git pkgs.nix];
      script = ''
        set -euo pipefail
        echo ":: Pulling latest from main..."
        git pull --ff-only origin main

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
