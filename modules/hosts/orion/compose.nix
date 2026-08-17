_: {
  flake.modules.nixos.orion-compose = _: {
    homelab.compose = {
      composeDir = "/home/erik/servarr/machines/orion";
      stacks = [
        "shared" # scrutiny-collector
        "monitoring" # prometheus-podman-exporter
        "ai-models" # llama-server (AMD Vulkan GPU)
        "sync" # restic backup
        # hermes-agent relocated to Discovery 2026-05-23 (always-on host)
      ];
    };
  };
}
