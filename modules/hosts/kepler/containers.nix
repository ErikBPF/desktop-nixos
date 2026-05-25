{config, ...}: {
  flake.modules.nixos.kepler-containers = {
    lib,
    pkgs,
    ...
  }: {
    # Kepler runs rootful Docker (matches Discovery). Rootless Podman on the
    # btrfs root subvol strips exec bits during OCI layer extraction in user
    # namespaces, breaking containers with exit 127. Same issue Discovery hit.

    virtualisation.podman.enable = lib.mkForce false;
    virtualisation.podman.dockerCompat = lib.mkForce false;

    virtualisation.docker = {
      enable = lib.mkForce true;
      enableOnBoot = true;
      autoPrune = {
        enable = true;
        dates = "weekly";
      };
      # NVIDIA runtime registered by hardware.nvidia-container-toolkit
      # (already enabled in default.nix). Containers opt in per-service with
      # `runtime: nvidia` — not made the default to avoid forcing GPU access
      # on stacks that don't need it (postgres, redis, etc.).
    };

    users.users.${config.username}.extraGroups = ["docker"];

    environment.systemPackages = [pkgs.docker-compose];
  };
}
