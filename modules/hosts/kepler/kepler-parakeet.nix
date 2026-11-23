_: {
  flake.modules.nixos.kepler-parakeet = {pkgs, ...}: let
    parakeet = pkgs.callPackage ../../packages/_parakeet-cpp.nix {};
  in {
    # Kepler's 8 GiB card holds whisper (:9000), parakeet (:9001) and
    # the 4B compose stack; measured VRAM peak is 6.4 GiB with 1.8 GiB free.
    # whisper and parakeet contend for the same compute queues (parakeet
    # 272 -> 933 ms when whisper runs concurrently); do not schedule both.
    systemd.services.parakeet-server = {
      description = "Parakeet.cpp ASR server (Vulkan)";
      wantedBy = ["multi-user.target"];
      environment.PARAKEET_DEVICE = "Vulkan0";
      # Vulkan keeps its shader cache under $HOME/.cache; ProtectHome blocks
      # the real home, so point HOME at a unit-private writable directory.
      environment.HOME = "/var/lib/parakeet";
      # /fast is a nofail ZFS dataset; order on the mount, not local-fs.
      unitConfig.RequiresMountsFor = "/fast/ai-models";
      serviceConfig = {
        User = "erik";
        StateDirectory = "parakeet";
        StateDirectoryMode = "0700";
        Group = "users";
        ExecStart = "${parakeet}/bin/parakeet-server --model /fast/ai-models/parakeet-cpp/tdt-0.6b-v3-f16.gguf --host 0.0.0.0 --port 9001";
        Restart = "always";
        RestartSec = 3;
        # /dev/dri access for the AMD GPU.
        SupplementaryGroups = ["video" "render"];
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
