_: {
  flake.modules.nixos.kepler-compose = _: {
    homelab.compose = {
      composeDir = "/home/erik/servarr/machines/kepler";
      # Rootful Docker — socket owned by root, accessible via docker group.
      dockerSocket = "unix:///run/docker.sock";
      stacks = [
        # Order matters: each unit waits for the previous via After=.
        # Start with the GPU-backed AI services. Heavier infra stacks
        # (postgres/redis, knowledge, photos, cicd, security) are intentionally
        # not auto-started yet — they will be re-introduced as their .yml
        # files are migrated off the legacy TrueNAS deployment.
        "ai-serving"
      ];
    };
  };
}
