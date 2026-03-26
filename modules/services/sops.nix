{...}: {
  flake.modules = {
    nixos.sops = {...}: {
      # NixOS-level sops is configured per-host (tailscale keys, etc.)
      # This module provides the base sops-nix enablement
    };

    home.sops = {
      config,
      lib,
      ...
    }: {
      sops = {
        age = {
          keyFile = "${config.home.homeDirectory}/.config/sops/age/keys.txt";
          generateKey = true;
        };
        defaultSopsFormat = "yaml";
        defaultSopsFile = ../../secrets/sops/secrets.yaml;
        secrets = {
          password = {};
          id_ed25519 = {};
          id_rsa = {};
        };
      };

      home.activation.copySopsSecrets = lib.hm.dag.entryAfter ["writeBoundary"] ''
        SOPS_DIR="$HOME/.config/sops-nix/secrets"

        if [ -f "$SOPS_DIR/id_ed25519" ]; then
          $DRY_RUN_CMD mkdir -p $HOME/.ssh
          $DRY_RUN_CMD cp -f "$SOPS_DIR/id_ed25519" $HOME/.ssh/id_ed25519
          $DRY_RUN_CMD chmod 0400 $HOME/.ssh/id_ed25519
        fi

        if [ -f "$SOPS_DIR/id_rsa" ]; then
          $DRY_RUN_CMD mkdir -p $HOME/.ssh
          $DRY_RUN_CMD cp -f "$SOPS_DIR/id_rsa" $HOME/.ssh/id_rsa
          $DRY_RUN_CMD chmod 0400 $HOME/.ssh/id_rsa
        fi
      '';
    };
  };
}
