{
  config,
  ...
}: let
  flakeConfig = config;
in {
  flake.modules.nixos.kepler-pqnld = {
    pkgs,
    lib,
    ...
  }: let
    # The household router reads the fine-tune's answer-slot logprobs and turns
    # them into a closed-set ha|escalate|noop decision with probabilities.
    descriptor = pkgs.writeText "finetune.json" (builtins.toJSON {
      readout = "auto";
      letters = "abcdefghijklmnopqrstuvwxyz";
      temperature = 1.0;
      enable_thinking = false;
      allow_partial_readout = true;
      system_prompt = "You are a decision engine. Read the state, then answer the question by replying with exactly one option key from the list. Do not explain.";
      letter_system_prompt = "You are a decision engine. Read the state, then answer the question by replying with exactly one option letter from the list. Do not explain.";
      engine_profile = "full";
    });
    modelsDir = pkgs.linkFarm "pqnld-models" [
      {
        name = "finetune.json";
        path = descriptor;
      }
    ];
  in {
    systemd.services.pqnld-router = {
      description = "pqnld typed decisions over the Kepler qwen4b fine-tune";
      wants = ["podman-compose-qwen4b-gpu.service"];
      after = ["podman-compose-qwen4b-gpu.service"];
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        ExecStart = lib.concatStringsSep " " [
          "${pkgs.pqnld}/bin/pqnld-rs"
          "--vllm-url http://127.0.0.1:8088"
          "--model qwen4b-v8-onpolicy-dpo-v9"
          "--descriptor finetune"
          "--models-dir ${modelsDir}"
          "--host ${flakeConfig.fleet.hosts.kepler.tailscaleIp}"
          "--port 11560"
          "--workers 2"
        ];
        Restart = "always";
        RestartSec = 10;
        DynamicUser = true;
      };
    };
  };
}
