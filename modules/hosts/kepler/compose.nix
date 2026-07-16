_: {
  flake.modules.nixos.kepler-compose = _: {
    homelab.compose = {
      composeDir = "/home/erik/servarr/machines/kepler";
      # Rootless Podman (matches existing kepler workloads). The orchestration
      # module's default socket path already targets this — left explicit for
      # readability and to make the dependency visible at the call site.
      dockerSocket = "unix:///run/user/1000/podman/podman.sock";
      stacks = [
        # Order matters: each unit waits for the previous via After=.
        # Qdrant in infra must precede docs-search. Other heavier stacks
        # (knowledge, photos, cicd, security) remain manual until migrated off
        # the legacy TrueNAS deployment.
        "infra"
        "whisper-gpu"
        "docs-search"
      ];
    };
  };
}
