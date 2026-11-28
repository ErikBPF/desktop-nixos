_: {
  flake.modules.nixos.orion-compose = _: {
    homelab.compose = {
      composeDir = "/home/erik/servarr/machines/orion";
      stacks = [
        "shared" # scrutiny-collector
        "monitoring" # prometheus-podman-exporter
        "sync" # restic backup
        "voice" # CPU transcription; independent of the active GPU chat stack
        # hermes-agent relocated to Discovery 2026-05-23 (always-on host)
      ];
    };
  };
}
