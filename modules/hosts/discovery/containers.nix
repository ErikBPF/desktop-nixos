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

    # Disable fleet-wide Podman for discovery.
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

    # Add erik to docker group so compose stacks run without sudo.
    users.users.${config.username}.extraGroups = ["docker"];

    environment.systemPackages = [pkgs.docker-compose];
  };
}
