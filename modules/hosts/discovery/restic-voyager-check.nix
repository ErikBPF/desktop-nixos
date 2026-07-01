# Weekly integrity check of the crown-jewel restic repos on voyager's
# append-only REST server (offsite-dr-crown-jewels §11 follow-up). Runs on
# discovery because the repo credentials (REST URLs + passwords) already live
# here for the backup jobs (vault.nix, restic-tofu-state.nix). Structural
# check + a rotating 10% pack read per run — full --read-data over the WAN is
# overkill for MB-scale config repos. rest-server --append-only still allows
# lock create/delete, so `restic check` works against it.
#
# On success (ExecStartPost pattern via script tail) writes a dead-man metric
# to the node_exporter textfile dir; Grafana alerts on staleness/absence
# (servarr discovery rules.yaml, uid restic-voyager-check-stale).
_: {
  flake.modules.nixos.discovery-restic-voyager-check = {
    config,
    pkgs,
    ...
  }: {
    systemd.services.restic-check-voyager = {
      description = "restic check of voyager offsite repos (openbao + tofu-state)";
      serviceConfig.Type = "oneshot";
      script = ''
        set -eu
        ${pkgs.restic}/bin/restic check --read-data-subset=10% \
          --repository-file ${config.sops.secrets."restic_vault_rest_url".path} \
          --password-file ${config.sops.secrets."vault_restic_password".path}
        ${pkgs.restic}/bin/restic check --read-data-subset=10% \
          --repository-file ${config.sops.secrets."restic_tofu_rest_url".path} \
          --password-file ${config.sops.secrets."restic_tofu_state_password".path}

        # Dead-man's-switch: only reached when both checks passed. Atomic write
        # (mktemp + mv) so the collector never reads a half-written file; 0644
        # so the alloy user can read what root wrote.
        d=/var/lib/node-exporter-textfile
        t=$(${pkgs.coreutils}/bin/date +%s)
        tmp=$(${pkgs.coreutils}/bin/mktemp "$d/.restic_voyager_check.XXXXXX")
        {
          echo "# HELP restic_voyager_check_last_success_seconds Unix time of last successful restic check of the voyager offsite repos."
          echo "# TYPE restic_voyager_check_last_success_seconds gauge"
          echo "restic_voyager_check_last_success_seconds $t"
        } > "$tmp"
        ${pkgs.coreutils}/bin/chmod 0644 "$tmp"
        ${pkgs.coreutils}/bin/mv "$tmp" "$d/restic_voyager_check.prom"
      '';
    };

    systemd.timers.restic-check-voyager = {
      wantedBy = ["timers.target"];
      timerConfig = {
        OnCalendar = "Sun *-*-* 05:00:00"; # off the 03:00-03:40 backup window
        Persistent = true;
        RandomizedDelaySec = "30m";
      };
    };
  };
}
