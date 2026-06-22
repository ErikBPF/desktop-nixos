{config, ...}: {
  flake.modules.nixos.discovery-containers = {
    lib,
    pkgs,
    ...
  }: let
    # Shared recovery pass: start any container that should be up but isn't.
    # `created` = made-but-never-started (an interrupted recreate, or a prune
    # leftover) → safe to start for any keep-up policy. `exited` could be a user
    # stop, so only force `always` back up. Never creates/duplicates containers,
    # so it's safe regardless of the (currently inconsistent) compose project
    # names — unlike `compose up`, which could spawn a second swag/adguard.
    recover = pkgs.writeShellScript "docker-recover" ''
      set -euo pipefail
      docker=${pkgs.docker}/bin/docker

      start_if() {
        name=$1
        shift
        policy=$("$docker" inspect -f '{{.HostConfig.RestartPolicy.Name}}' "$name" 2>/dev/null || echo none)
        for p in "$@"; do
          if [ "$policy" = "$p" ]; then
            echo "docker-recover: starting $name (policy=$policy)"
            "$docker" start "$name" || echo "docker-recover: FAILED to start $name" >&2
            return
          fi
        done
      }

      for name in $("$docker" ps -a --filter status=created --format '{{.Names}}'); do
        start_if "$name" always unless-stopped
      done
      for name in $("$docker" ps -a --filter status=exited --format '{{.Names}}'); do
        start_if "$name" always
      done
    '';
  in {
    # Discovery uses Docker instead of rootless Podman.
    #
    # Rootless Podman on btrfs suffers from a kernel overlayfs issue where
    # execute bits (755) are stripped to 711 during OCI layer extraction in
    # user namespaces, causing containers to fail with exit 127. fuse-overlayfs
    # as mount_program fixes the *mount* path but not the *extraction* path —
    # the issue is in the kernel btrfs+userns interaction before fuse-overlayfs
    # is involved.
    #
    # TODO: Re-evaluate rootless Podman on btrfs in a future NixOS/Podman/kernel
    # version. The fix likely requires either:
    #   a) kernel fix for btrfs+userns inode permission handling, or
    #   b) moving container storage to a non-btrfs filesystem (e.g. ext4 subvol)
    # Track: https://github.com/containers/podman/issues (btrfs 711 permissions)

    # Defensive: profile-base no longer pulls in Podman, but keep the force-off
    # in case m.nixos.containers ever lands here via another import path.
    virtualisation.podman.enable = lib.mkForce false;
    virtualisation.podman.dockerCompat = lib.mkForce false;

    # Enable Docker (rootful) — runs as daemon, no user namespace issues.
    virtualisation.docker = {
      enable = lib.mkForce true;
      enableOnBoot = true;
      autoPrune = {
        enable = true;
        dates = "weekly";
      };
    };

    # Recovery — runs the shared `recover` pass two ways:
    #
    # 1. ExecStartPost of docker-prune.service: the weekly `docker system prune
    #    -f` can leave a container `created` (observed 2026-06-08: adguard came
    #    back `created` right after the Mon 00:00 prune). restart=unless-stopped
    #    can't recover a never-started container.
    # 2. A standalone 3-min timer (below): the prune hook only fires weekly, so a
    #    mid-week interrupted recreate (observed 2026-06-22: adguard left
    #    `created` at 01:14, DNS down for hours) wouldn't heal until next Monday.
    #    The timer closes that gap — any down-but-should-be-up container is back
    #    within ~3 min.
    systemd.services.docker-prune.serviceConfig.ExecStartPost = "${recover}";

    systemd.services.docker-recover = {
      description = "Heal containers left created/exited that should be running";
      after = ["docker.service"];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${recover}";
      };
    };
    systemd.timers.docker-recover = {
      description = "Periodic docker recovery (heals e.g. AdGuard DNS within ~3 min)";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnBootSec = "2min";
        OnUnitActiveSec = "3min";
        Persistent = true;
      };
    };

    # Add erik to docker group so compose stacks run without sudo.
    users.users.${config.username}.extraGroups = ["docker"];

    environment.systemPackages = [pkgs.docker-compose];
  };
}
