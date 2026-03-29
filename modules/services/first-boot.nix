{config, ...}: {
  flake.modules.nixos.first-boot = {lib, ...}: let
    inherit (config) username;
    homeDir = "/home/${username}";
  in {
    # Distribute sops age key from staging path to user home
    system.activationScripts.distributeSopsKey = {
      text = ''
        STAGING="/var/lib/sops-staging/age-keys.txt"
        TARGET="${homeDir}/.config/sops/age/keys.txt"
        # Copy from staging if target doesn't exist yet
        if [ -f "$STAGING" ] && [ ! -f "$TARGET" ]; then
          mkdir -p "$(dirname "$TARGET")"
          cp "$STAGING" "$TARGET"
        fi
        # Clean up staging after copy
        if [ -f "$STAGING" ] && [ -f "$TARGET" ]; then
          rm "$STAGING"
        fi
        # Always fix ownership (handles nixos-install leaving root-owned files)
        if [ -f "$TARGET" ]; then
          chown -R ${username}:users "${homeDir}/.config/sops" 2>/dev/null || true
          chmod 600 "$TARGET"
        fi
      '';
      deps = ["users"];
    };

    # Fix home directory ownership (extra-files leaves root-owned dirs)
    system.activationScripts.fixHomePermissions = {
      text = ''
        chown ${username}:users ${homeDir}/.config 2>/dev/null || true
      '';
      deps = ["users"];
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

    # Re-run sops decryption after SSH host keys are generated on first boot.
    # sops-nix activation fails during nixos-install because host keys don't exist yet.
    # This oneshot runs once after sshd generates keys, re-activates sops, then restarts
    # any services that depend on decrypted secrets.
    systemd.services.sops-first-boot = {
      description = "Re-run sops decryption after first-boot SSH key generation";
      wantedBy = ["multi-user.target"];
      after = ["sshd.service"];
      requires = ["sshd.service"];
      unitConfig.ConditionPathExists = "!/run/secrets/tailscale_authkey";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "/run/current-system/activate";
        ExecStartPost = "/run/current-system/sw/bin/systemctl restart tailscaled-autoconnect.service";
      };
    };
  };
}
