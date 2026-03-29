{
  config,
  inputs,
  ...
}: {
  flake.modules.nixos.common = {...}: {
    time.timeZone = "America/Sao_Paulo";

    nixpkgs = {
      overlays = [
        (final: _prev: {
          quickshell = inputs.quickshell.packages.${final.system}.default;
        })
      ];
      config.allowUnfree = true;
    };

    documentation = {
      enable = false;
      doc.enable = false;
      man.enable = false;
      dev.enable = false;
      info.enable = false;
      nixos.enable = false;
    };

    nix = {
      settings = {
        warn-dirty = false;
        experimental-features = ["nix-command" "flakes"];
        auto-optimise-store = true;
        max-jobs = "auto";
        cores = 0;
        trusted-users = ["root" config.username];
        fallback = true;
        substituters = [
          "https://cache.nixos.org?priority=10"
          # "https://nix-cache.homelab.pastelariadev.com?priority=5" # TODO: enable after Epic 3 deploys nix-serve
          "https://nix-community.cachix.org"
          "https://hyprland.cachix.org"
        ];
        trusted-public-keys = [
          "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
          "discovery:mKNAVuDlUSFOiRqj7gnVDfVkLVbh9XBWG6X68LRvjnk="
          "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
          "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
        ];
      };

      gc = {
        automatic = true;
        dates = "daily";
        options = "--delete-older-than 3d";
      };
    };
  };
}
