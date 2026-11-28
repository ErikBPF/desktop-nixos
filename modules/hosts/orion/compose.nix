_: {
  flake.modules.nixos.orion-compose = _: {
    homelab.compose = {
      composeDir = "/home/erik/servarr/machines/orion";
      stacks = [
        "shared" # scrutiny-collector
        "monitoring" # prometheus-podman-exporter
        "sync" # restic backup
        # hermes-agent relocated to Discovery 2026-05-23 (always-on host)
        # voice retired 2026-11-28 — ASR stays on Kepler, no Orion ASR server.
      ];
    };
  };
}
