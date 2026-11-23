_: {
  flake.modules.home.voice-dictation = {
    config,
    pkgs,
    lib,
    ...
  }: let
    voxtype = pkgs.voxtype.override {onnxSupport = true;};
    runtime = with pkgs; [voxtype python3 systemd wl-clipboard libnotify coreutils pipewire];
    controller = pkgs.writeShellApplication {
      name = "voice-dictation";
      runtimeInputs = runtime;
      text = ''exec python3 ${./_voice_dictation.py} "$@"'';
    };
    modelFiles = {
      "encoder-model.int8.onnx" = "6139d2fa7e1b086097b277c7149725edbab89cc7c7ae64b23c741be4055aff09";
      "decoder_joint-model.int8.onnx" = "eea7483ee3d1a30375daedc8ed83e3960c91b098812127a0d99d1c8977667a70";
      "vocab.txt" = "d58544679ea4bc6ac563d1f545eb7d474bd6cfa467f0a6e2c1dc1c7d37e3c35d";
      "config.json" = "666903c76b9798caf2c210afd4f6cd60b08a8dbf9800ec8d7a3bc0d2148ac466";
    };
    model = pkgs.linkFarm "parakeet-tdt-0.6b-v3-int8" (lib.mapAttrsToList (name: sha256: {
        inherit name;
        path = pkgs.fetchurl {
          url = "https://models.voxtype.io/parakeet/parakeet-tdt-0.6b-v3-int8/${name}";
          inherit sha256;
        };
      })
      modelFiles);
    toml = pkgs.formats.toml {};
    transcriberConfig = toml.generate "voice-transcriber.toml" {
      engine = "parakeet";
      state_file = "auto";
      hotkey.enabled = false;
      osd.enabled = false;
      parakeet = {
        model = "${model}";
        model_type = "tdt";
        on_demand_loading = true;
      };
      audio.max_duration_secs = 120;
      output = {
        mode = "file";
        file_path = "/dev/null";
        auto_submit = false;
        fallback_to_clipboard = false;
        notification.on_transcription = false;
      };
    };
    # Dedicated config avoids overwriting an independently configured Voxtype app.
    configuredVoxtype = pkgs.writeShellScriptBin "voxtype" ''
      exec ${voxtype}/bin/voxtype --config ${transcriberConfig} "$@"
    '';
    binding = key: mode: {
      _args = [key (lib.generators.mkLuaInline ''hl.dsp.exec_cmd("${controller}/bin/voice-dictation toggle ${mode}")'')];
    };
  in {
    home.packages = [controller];
    systemd.user.services.voice-rewrite = {
      Unit.Description = "Local dictation rewrite model";
      Service = {
        ExecStart = "${pkgs.ollama}/bin/ollama serve";
        Environment = ["OLLAMA_HOST=127.0.0.1:11435" "OLLAMA_MODELS=${config.xdg.dataHome}/voice-dictation/ollama" "OLLAMA_NO_CLOUD=1"];
        Restart = "on-failure";
        UMask = "0077";
      };
      Install.WantedBy = ["default.target"];
    };
    systemd.user.services."voice-dictation@" = {
      Unit = {
        Description = "Dictation capture (%i)";
        Wants = ["voice-rewrite.service"];
        After = ["pipewire.service" "voice-rewrite.service"];
      };
      Service = {
        ExecStart = "${pkgs.python3}/bin/python3 ${./_voice_dictation.py} worker %i";
        Environment = [
          "PATH=${lib.makeBinPath ([configuredVoxtype] ++ runtime)}"
          "RUST_LOG=error"
          "VOICE_API_KEY_FILE=${config.xdg.configHome}/voice-dictation/litellm-api-key"
        ];
        UMask = "0077";
        TimeoutStopSec = 10;
      };
    };
    wayland.windowManager.hyprland.settings.bind = [
      (binding "SUPER + U" "plain")
      (binding "SUPER + I" "context")
      (binding "SUPER + CTRL + I" "cancel")
    ];
  };
}
