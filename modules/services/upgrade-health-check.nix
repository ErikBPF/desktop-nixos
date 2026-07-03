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
        Units that must be active after an unattended upgrade; otherwise the
        previous generation is re-activated. A host definition replaces the
        default — re-list the default units when overriding.
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

        # Reachability probe. is-active can pass while the host is network-dark —
        # the switch broke the interface/routing/uplink but sshd/tailscaled stay
        # "active", so the loop above misses it and the host silently locks out
        # (the exact failure class deploy-rs magic rollback catches and this
        # module previously did not). Ping the default gateway; roll back only if
        # it stays unreachable across retries, to tolerate a transient blip while
        # networking re-settles after activation.
        gw="$(${pkgs.iproute2}/bin/ip route show default | ${pkgs.gawk}/bin/awk '/default/{print $3; exit}')"
        if [ -n "$gw" ]; then
          reachable=0
          for _ in 1 2 3 4 5 6; do
            if ${pkgs.iputils}/bin/ping -c1 -W2 "$gw" >/dev/null 2>&1; then reachable=1; break; fi
            sleep 5
          done
          if [ "$reachable" -ne 1 ]; then
            echo "HEALTH CHECK: default gateway $gw unreachable after upgrade — rolling back" >&2
            ${pkgs.nix}/bin/nix-env --profile /nix/var/nix/profiles/system --rollback
            /nix/var/nix/profiles/system/bin/switch-to-configuration switch
            exit 1
          fi
        fi
        echo "Health check passed: critical units active and gateway reachable"
      '');
    };
  };
}
