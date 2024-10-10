{
  config,
  pkgs,
  inputs,
  lib,
  ...
}: {
  imports = [
    ./nh.nix
    ./nixpkgs.nix
    ./substituters.nix
  ];

  # we need git for flakes
  environment.systemPackages = [pkgs.git];

  services.xserver = {
    # ...

    xkb = {
      layout = "qwerty-fr";
      variant = "qwerty-fr";
      extraLayouts = {
        qwerty-fr = {
          description = "QWERTY with French symbols and diacritics";
          languages = ["eng"];
          symbolsFile = https://raw.githubusercontent.com/ErikBPF/desktop-nixos/refs/heads/test-kaku/system/nix/us_qwerty-fr;
        };
      };
    };
  };

  nix = {
    package = pkgs.lix;

    # pin the registry to avoid downloading and evaling a new nixpkgs version every time
    registry = lib.mapAttrs (_: v: {flake = v;}) inputs;

    # set the path for channels compat
    nixPath = lib.mapAttrsToList (key: _: "${key}=flake:${key}") config.nix.registry;

    settings = {
      warn-dirty = false;
      auto-optimise-store = true;
      builders-use-substitutes = true;
      experimental-features = ["nix-command" "flakes"];
      flake-registry = "/etc/nix/registry.json";

      # for direnv GC roots
      keep-derivations = true;
      keep-outputs = true;

      trusted-users = ["root" "@wheel"];
    };

    distributedBuilds = true;
  };
}
