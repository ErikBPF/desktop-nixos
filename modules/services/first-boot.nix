{config, ...}: {
  flake.modules.nixos.first-boot = {lib, ...}: let
    username = config.username;
    homeDir = "/home/${username}";
  in {
    # Distribute sops age key from staging path to user home
    system.activationScripts.distributeSopsKey = {
      text = ''
        STAGING="/var/lib/sops-staging/age-keys.txt"
        TARGET="${homeDir}/.config/sops/age/keys.txt"
        if [ -f "$STAGING" ] && [ ! -f "$TARGET" ]; then
          mkdir -p "$(dirname "$TARGET")"
          cp "$STAGING" "$TARGET"
          chown -R ${username}:users "${homeDir}/.config/sops"
          chmod 600 "$TARGET"
          rm "$STAGING"
        fi
      '';
      deps = [];
    };

    # Fix home directory ownership (extra-files leaves root-owned dirs)
    system.activationScripts.fixHomePermissions = {
      text = ''
        chown ${username}:users ${homeDir}/.config 2>/dev/null || true
      '';
      deps = [];
    };

    # Home-manager retry on failure (first boot race condition)
    systemd.services."home-manager-${username}" = {
      serviceConfig = {
        Restart = lib.mkDefault "on-failure";
        RestartSec = lib.mkDefault "5s";
      };
      unitConfig = {
        StartLimitIntervalSec = lib.mkDefault 120;
        StartLimitBurst = lib.mkDefault 5;
      };
    };
  };
}
