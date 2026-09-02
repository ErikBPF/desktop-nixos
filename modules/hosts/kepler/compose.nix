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
        # Security precedes sync because Ofelia starts in sync and discovers
        # labeled jobs only once. Other heavier stacks
        # (knowledge, photos, cicd) remain manual until migrated off
        # the legacy TrueNAS deployment.
        "infra"
        "buzz"
        "monitoring"
        "security"
        "sync"
        "whisper-gpu"
        "qwen4b-gpu"
        "retrieval"
      ];
    };
  };
}
