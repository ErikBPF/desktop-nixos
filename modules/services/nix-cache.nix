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
      # nix-serve-ng is the maintained drop-in: a GHC-built executable that
      # links the Nix store library, already cached by Hydra for this nixpkgs,
      # so it substitutes instead of rebuilding. The perl nix-serve in this
      # nixpkgs ships no Nix perl modules, so every child died with
      # "Can't locate Nix/Config.pm" and the cache crash-looped while every host
      # fell back to cache.nixos.org. nix-serve-ng parses the module's
      # `--listen addr:port` for drop-in compatibility, so the rest of the
      # module (DynamicUser, LoadCredential, Restart=always) stays as it was.
      package = pkgs.nix-serve-ng;
      bindAddress = "0.0.0.0";
      port = 5000;
      secretKeyFile = config.sops.secrets.nix_cache_signing_key.path;
    };

    networking.firewall.interfaces.enp4s0.allowedTCPPorts = [5000];
    networking.firewall.interfaces.tailscale0.allowedTCPPorts = [5000];

    # Daily closure builder — keeps the cache warm by building all host closures.
    # Runs at 22:00, requires the flake repo to be checked out at the path below.
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
        StateDirectory = "nix-cache-builder";
        WorkingDirectory = "/var/lib/nix-cache-builder";
      };
      path = [pkgs.git pkgs.nix pkgs.coreutils];
      script = ''
        set -euo pipefail
        if [ ! -d repo/.git ]; then
          git clone --branch main --single-branch \
            https://github.com/ErikBPF/desktop-nixos.git repo
        fi
        cd repo
        echo ":: Syncing repo to origin/main..."
        git fetch --prune origin
        git reset --hard origin/main

        # One host's broken closure must not skip the others' warm (observed
        # 2026-07-02: one unavailable fixed-output aborted the run before the
        # remaining hosts were built). Build one host at a time so a slow
        # closure cannot consume the whole timeout without naming itself, and
        # fail the unit at the end so the failure still surfaces.
        # 9 hosts x 40 min stays inside the 359 min unit ceiling in
        # modules/hosts/orion/default.nix.
        echo ":: Building host closures..."
        failed=()
        for host in apollo archinaut discovery kepler orion pathfinder telstar vanguard voyager; do
          started=$(date -u +%FT%TZ)
          if timeout 2400 nix build --no-link --keep-going \
            ".#nixosConfigurations.$host.config.system.build.toplevel"; then
            echo ":: $host ok ($started -> $(date -u +%FT%TZ))"
          else
            status=$?
            echo ":: $host FAILED status=$status ($started -> $(date -u +%FT%TZ))" >&2
            failed+=("$host")
          fi
        done
        if [ ''${#failed[@]} -gt 0 ]; then
          echo ":: Cache builder failed for: ''${failed[*]}" >&2
          exit 1
        fi
        echo ":: Cache builder complete"
      '';
    };

    systemd.timers.nix-cache-builder = {
      description = "Daily nix cache builder timer";
      wantedBy = ["timers.target"];
      timerConfig = {
        # 22:00, not 03:00: the warm needs up to the 359 min unit ceiling in
        # modules/hosts/orion/default.nix, and the fleet's autoUpgrade herd
        # substitutes at 05:00. Starting at 03:00 put the tail of the build
        # inside that window; starting at 22:00 leaves ~7h to finish first.
        OnCalendar = "22:00";
        Persistent = true;
      };
    };

    # nix-serve (starman) can end up with every worker blocked on clients from
    # aborted builds: the process stays "active" while new requests time out,
    # which then wedges every host's switch for hours. A cheap liveness probe
    # restarts it before that becomes an outage.
    systemd.services.nix-serve-health = {
      description = "Restart nix-serve when it stops answering";
      serviceConfig = {
        Type = "oneshot";
        User = "root";
      };
      script = ''
        if ! ${pkgs.curl}/bin/curl -fsS --max-time 10 \
          http://127.0.0.1:5000/nix-cache-info >/dev/null; then
          echo "nix-serve did not answer; restarting" >&2
          systemctl restart nix-serve.service
        fi
      '';
    };

    systemd.timers.nix-serve-health = {
      description = "Probe nix-serve liveness";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnBootSec = "10min";
        OnUnitActiveSec = "5min";
        Persistent = false;
      };
    };
  };
}
