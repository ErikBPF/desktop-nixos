_: {
  flake.modules.nixos.upgrade-health-check = {
    config,
    pkgs,
    lib,
    ...
  }: {
    options.modules.upgradeHealthCheck.criticalUnits = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = ["sshd.service" "tailscaled.service"];
      description = ''
        Units that must be active after an unattended upgrade. If any is not,
        the system profile is rolled back and the previous generation
        re-activated. Hosts overriding this must re-list sshd/tailscaled —
        a definition replaces the default.
      '';
    };

    # After nixos-rebuild switch completes, verify the critical units are
    # still alive. If not, roll back the system profile and re-activate the
    # previous generation. This prevents a bad upgrade from silently locking
    # out remote access or taking core services down.
    config = lib.mkIf config.system.autoUpgrade.enable {
      systemd.services.nixos-upgrade.serviceConfig.ExecStartPost = toString (pkgs.writeShellScript "nixos-upgrade-health-check" ''
        set -euo pipefail
        # Give systemd a moment to settle new units after activation
        sleep 3
        for unit in ${lib.escapeShellArgs config.modules.upgradeHealthCheck.criticalUnits}; do
          if ! ${pkgs.systemd}/bin/systemctl is-active --quiet "$unit"; then
            echo "HEALTH CHECK: $unit not active after upgrade — rolling back" >&2
            ${pkgs.nix}/bin/nix-env --profile /nix/var/nix/profiles/system --rollback
            /nix/var/nix/profiles/system/bin/switch-to-configuration switch
            exit 1
          fi
        done
        echo "Health check passed: all critical units active"
      '');
    };
  };
}
