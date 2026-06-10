_: {
  flake.modules.nixos.orion-containers = _: {
    # Podman/dockerCompat comes from m.nixos.containers, imported explicitly
    # in default.nix (no longer part of profile-base).
    # homelab-net network is created by docker compose — compose handles it declaratively.
  };
}
