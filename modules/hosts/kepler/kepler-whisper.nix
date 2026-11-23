_: {
  flake.modules.nixos.kepler-whisper = {pkgs, ...}: let
    whisper = pkgs.whisper-cpp;
  in {
    systemd.services.whisper-server = {
      description = "whisper.cpp ASR server (Vulkan)";
      wantedBy = ["multi-user.target"];
      # Vulkan writes its shader cache under $HOME/.cache; ProtectHome blocks
      # the real home, so point HOME at a unit-private writable directory.
      environment = {
        HOME = "/var/lib/whisper";
        XDG_CACHE_HOME = "/var/lib/whisper/.cache";
      };
      # /fast is a nofail ZFS dataset; order on the mount, not local-fs.
      unitConfig.RequiresMountsFor = "/fast/ai-models";
      serviceConfig = {
        User = "erik";
        Group = "users";
        StateDirectory = "whisper";
        StateDirectoryMode = "0700";
        ExecStart = "${whisper}/bin/whisper-server --model /fast/ai-models/whisper-ggml/ggml-large-v3-turbo.bin --host 0.0.0.0 --port 9000 -l auto --inference-path /v1/audio/transcriptions";
        Restart = "always";
        RestartSec = 3;
        SupplementaryGroups = [
          "video"
          "render"
        ];
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadOnlyPaths = ["/fast/ai-models"];
        ProtectKernelTunables = true;
        ProtectControlGroups = true;
      };
    };
  };
}
