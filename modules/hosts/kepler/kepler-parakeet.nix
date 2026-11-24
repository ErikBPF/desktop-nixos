_: {
  flake.modules.nixos.kepler-parakeet = {pkgs, ...}: let
    parakeet = pkgs.callPackage ../../packages/_parakeet-cpp.nix {};
  in {
    # Kepler's single 8 GiB card: 8 176 MiB total, measured VRAM peak 6 389 MiB
    # with 1 787 MiB free while whisper (:9000), parakeet (:9001) and the 4B
    # stack are resident. Whisper and parakeet share compute queues, so an
    # overlapping ASR request measured parakeet at 933 ms instead of 272 ms;
    # both remain resident and callers should avoid overlapping ASR jobs.
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
