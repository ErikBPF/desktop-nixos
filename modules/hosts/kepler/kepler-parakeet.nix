_: {
  flake.modules.nixos.kepler-parakeet = {pkgs, ...}: let
    parakeet = pkgs.callPackage ../../packages/_parakeet-cpp.nix {};
  in {
    systemd.services.parakeet-server = {
      description = "Parakeet.cpp ASR server (Vulkan)";
      wantedBy = ["multi-user.target"];
      environment.PARAKEET_DEVICE = "Vulkan0";
      # /fast is a nofail ZFS dataset; order on the mount, not local-fs.
      unitConfig.RequiresMountsFor = "/fast/ai-models";
      serviceConfig = {
        User = "erik";
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
