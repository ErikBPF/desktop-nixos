{config, ...}: {
  flake.modules.nixos.common = _: {
    time.timeZone = "America/Sao_Paulo";

    nixpkgs = {
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
        # Redirect build sandboxes off tmpfs → saves RAM on memory-constrained hosts
        build-dir = "/nix/build-tmp";
        # Allow build machines to fetch from substituters directly
        builders-use-substitutes = true;
        connect-timeout = 5;
        substituters = [
          "https://cache.nixos.org?priority=10"
          "http://192.168.10.220:5000?priority=5"
          "https://nix-community.cachix.org"
          "https://hyprland.cachix.org"
        ];
        trusted-public-keys = [
          "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
          "orion:4hKV3v/D0wY4JIk1TIcgaBIjM9VliJnwZyRUjCZhtSg="
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

    # Build scratch dir owned by root (nix rejects world-writable build-dir)
    systemd.tmpfiles.rules = [
      "d /nix/build-tmp 0700 root root -"
    ];
  };
}
