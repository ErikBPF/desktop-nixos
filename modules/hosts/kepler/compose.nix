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
        # qwen4b-gpu and retrieval-vulkan serve on the AMD Vulkan path.
        # Co-resident budget measured 2026-11-24 on the 8 176 MiB card:
        # whisper :9000, parakeet :9001, Qwen 8k, BGE embedder 8k and
        # reranker 2k hold 7 702 MiB VRAM, leaving about 474 MiB free; a
        # 3 000-token Qwen prompt peaks at 7 744 MiB (about 432 MiB free).
        # A further 796 MiB sits in GTT (system-RAM spill) and is outside
        # the 8 176 MiB VRAM total. "whisper-gpu" stays paused.
        # "whisper-gpu"
        "qwen4b-gpu"
        "retrieval-vulkan"
        # "retrieval"
      ];
    };
  };
}
