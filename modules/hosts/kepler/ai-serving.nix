{self, ...}: {
  flake.modules.nixos.kepler-ai-serving = {
    config,
    pkgs,
    ...
  }: {
    # LAN-only exposure. Discovery (LiteLLM + HAOS) reaches kepler via LAN,
    # Wyoming protocol is unauthenticated and must not leave the network.
    #   8001  f5-tts               (OpenAI /v1/audio/speech)
    #   8085  bge-m3               (OpenAI /v1/embeddings)
    #   8087  bge-reranker-v2-m3   (Cohere /v1/rerank)
    #   9000  faster-whisper       (OpenAI /v1/audio/transcriptions; HA STT here too)
    #  10200  wyoming-piper        (HA fallback TTS)
    # 10300 (wyoming-whisper) intentionally removed — see ai-serving.yml.
    networking.firewall.allowedTCPPorts = [8001 8002 8003 8085 8087 9000 10200];

    # Model cache lives on fast-pool (ZFS RAIDZ1, ~1.4 TB). Survives
    # docker compose down/up and image rebuilds. Pre-create with the
    # subdirs each container expects.
    systemd.tmpfiles.rules = [
      "d /fast/ai-models 0755 erik users -"
      "d /fast/ai-models/whisper 0755 erik users -"
      "d /fast/ai-models/f5-tts 0755 erik users -"
      "d /fast/ai-models/embeddings 0755 erik users -"
      "d /fast/ai-models/refs 0755 erik users -"
      "d /fast/ai-models/piper 0755 erik users -"
      "d /fast/ai-models/vlm 0755 erik users -"
    ];

    # The servarr .env.sops carries HF_TOKEN + service env. The orchestration
    # module's servarr-pull service decrypts it to .env via `sops`. No
    # additional sops secret is registered here — that flow is shared with
    # every other host and lives in the servarr repo.
    _module.args.keplerAiServing = {};
  };
}
