_: {
  flake.modules.nixos.orchestration = _: {
    # Container orchestration defaults for server hosts.
    # Podman/dockerCompat is enabled by profile-base → containers module.
  };
}
