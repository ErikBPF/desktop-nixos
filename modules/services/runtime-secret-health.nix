_: {
  flake.modules.nixos.runtime-secret-health = {pkgs, ...}: let
    probe = pkgs.writeShellScript "runtime-secret-health" ''
      set -eu
      ready=0
      for path in /run/secrets /run/user/1000/secrets; do
        if [ -d "$path" ] && [ -n "$(${pkgs.findutils}/bin/find -L "$path" -mindepth 1 -maxdepth 1 -type f -print -quit)" ]; then
          ready=1
          break
        fi
      done
      output=/var/lib/node-exporter-textfile/sops-runtime-secrets.prom
      printf 'sops_runtime_secrets_ready %s\n' "$ready" > "$output.tmp"
      ${pkgs.coreutils}/bin/mv "$output.tmp" "$output"
    '';
  in {
    systemd.services.runtime-secret-health = {
      description = "Export Sops runtime secret readiness";
      unitConfig.ConditionPathExists = "/var/lib/node-exporter-textfile";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${probe}";
      };
    };

    systemd.timers.runtime-secret-health = {
      wantedBy = ["timers.target"];
      timerConfig = {
        OnBootSec = "1m";
        OnUnitActiveSec = "1m";
      };
    };
  };
}
