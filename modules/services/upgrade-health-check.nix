_: {
  flake.modules.nixos.upgrade-health-check = {
    config,
    pkgs,
    lib,
    ...
  }: {
    options.modules.upgradeHealthCheck = {
      criticalUnits = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        readOnly = true;
        default = ["sshd.service" "tailscaled.service"] ++ config.modules.upgradeHealthCheck.extraCriticalUnits;
        description = "Units that must be active after an unattended upgrade.";
      };
      extraCriticalUnits = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = "Host-specific units appended to the immutable SSH and Tailscale checks.";
      };
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
        # module previously did not). Probe a routed public HTTPS endpoint;
        # gateway service ports vary by network and caused false rollbacks.
        # Roll back only if TCP/443 stays unreachable across retries,
        # tolerating a transient blip while networking re-settles.
        probe=1.1.1.1
        reachable=0
        for _ in 1 2 3 4 5 6; do
          if ${pkgs.coreutils}/bin/timeout 2 ${pkgs.bash}/bin/bash -c "exec 3<>/dev/tcp/$probe/443"; then reachable=1; break; fi
          sleep 5
        done
        if [ "$reachable" -ne 1 ]; then
          echo "HEALTH CHECK: routed TCP/443 unreachable after upgrade — rolling back" >&2
          ${pkgs.nix}/bin/nix-env --profile /nix/var/nix/profiles/system --rollback
          /nix/var/nix/profiles/system/bin/switch-to-configuration switch
          exit 1
        fi
        echo "Health check passed: critical units active and routed network reachable"
      '');

      # Retry a failed unattended upgrade once, anchored to that run rather
      # than to a wall-clock time: hosts schedule nightly (discovery,
      # pathfinder, with up to 15 min of jitter) or weekly (archinaut), so a
      # fixed retry time would fire on days the host never upgraded or miss a
      # jittered run that was still activating. OnFailure fires immediately
      # after the failed run, which is inside the reboot window.
      #
      # OnFailure also fires for the retried run, so a failed retry would
      # retrigger itself. The 6h marker bounds it to one attempt per failure.
      systemd.services.nixos-upgrade.serviceConfig.OnFailure = [
        "nixos-upgrade-retry.service"
      ];

      systemd.services.nixos-upgrade-retry = {
        description = "Retry a failed unattended upgrade once";
        serviceConfig = {
          Type = "oneshot";
          User = "root";
        };
        script = ''
          marker=/run/nixos-upgrade-retry.last
          now=$(${pkgs.coreutils}/bin/date +%s)
          if [ -e "$marker" ] && \
            [ $((now - $(${pkgs.coreutils}/bin/stat -c %Y "$marker"))) -lt 21600 ]; then
            echo "retry already attempted within 6h; not retrying" >&2
            exit 0
          fi
          ${pkgs.coreutils}/bin/touch "$marker"
          echo "nixos-upgrade failed; retrying once" >&2
          ${pkgs.systemd}/bin/systemctl reset-failed nixos-upgrade.service
          ${pkgs.systemd}/bin/systemctl start nixos-upgrade.service
        '';
      };
    };
  };
}
