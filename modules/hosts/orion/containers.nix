_: {
  flake.modules.nixos.orion-containers = _: {
    # Podman/dockerCompat is enabled fleet-wide by profile-base → containers module.
    # homelab-net network is created by docker compose — compose handles it declaratively.
  };
}
