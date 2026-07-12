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
        # Start with the GPU-backed AI services. Heavier infra stacks
        # (postgres/redis, knowledge, photos, cicd, security) are intentionally
        # not auto-started yet — they will be re-introduced as their .yml
        # files are migrated off the legacy TrueNAS deployment.
        "ai-serving"
        "docs-search"
      ];
    };
  };
}
