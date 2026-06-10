{config, ...}: {
  flake.modules.nixos.discovery-containers = {
    lib,
    pkgs,
    ...
  }: {
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

    # Post-prune recovery.
    #
    # The weekly `docker system prune -f` can leave a container in the
    # `created` state — made but never started (observed 2026-06-08: adguard
    # came back as `created` right after the Mon 00:00 prune). A restart
    # policy of `unless-stopped`/`always` cannot recover a never-started
    # container, so it stays down silently until something queries it.
    #
    # Run a recovery pass as ExecStartPost of docker-prune.service: same root
    # scope, fires after every prune, no extra timer. It only touches
    # containers whose own restart policy says they should be up, and never
    # resurrects a deliberately user-stopped (`unless-stopped` + `exited`)
    # container.
    systemd.services.docker-prune.serviceConfig.ExecStartPost = let
      recover = pkgs.writeShellScript "docker-prune-recover" ''
        set -euo pipefail
        docker=${pkgs.docker}/bin/docker

        start_if() {
          name=$1
          shift
          policy=$("$docker" inspect -f '{{.HostConfig.RestartPolicy.Name}}' "$name" 2>/dev/null || echo none)
          for p in "$@"; do
            if [ "$policy" = "$p" ]; then
              echo "docker-prune-recover: starting $name (policy=$policy)"
              "$docker" start "$name" || echo "docker-prune-recover: FAILED to start $name" >&2
              return
            fi
          done
        }

        # created = never started -> safe to bring up for any "keep it up" policy.
        for name in $("$docker" ps -a --filter status=created --format '{{.Names}}'); do
          start_if "$name" always unless-stopped
        done

        # exited = could be a user-initiated stop; only force `always` back up.
        for name in $("$docker" ps -a --filter status=exited --format '{{.Names}}'); do
          start_if "$name" always
        done
      '';
    in "${recover}";

    # Add erik to docker group so compose stacks run without sudo.
    users.users.${config.username}.extraGroups = ["docker"];

    environment.systemPackages = [pkgs.docker-compose];
  };
}
