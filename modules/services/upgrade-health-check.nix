_: {
  flake.modules.nixos.upgrade-health-check = {
    config,
    pkgs,
    lib,
    ...
  }:
    lib.mkIf config.system.autoUpgrade.enable {
      # After nixos-rebuild switch completes, verify sshd is still alive.
      # If not, roll back the system profile and re-activate the previous generation.
      # This prevents a bad upgrade from silently locking out remote access.
      systemd.services.nixos-upgrade.serviceConfig.ExecStartPost = toString (pkgs.writeShellScript "nixos-upgrade-health-check" ''
        set -euo pipefail
        # Give systemd a moment to settle new units after activation
        sleep 3
        if ! ${pkgs.systemd}/bin/systemctl is-active --quiet sshd.service; then
          echo "HEALTH CHECK: sshd not active after upgrade — rolling back" >&2
          ${pkgs.nix}/bin/nix-env --profile /nix/var/nix/profiles/system --rollback
          /nix/var/nix/profiles/system/bin/switch-to-configuration switch
          exit 1
        fi
        echo "Health check passed: sshd is active"
      '');
    };
}
