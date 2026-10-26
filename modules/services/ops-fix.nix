{inputs, ...}: {
  flake.modules.nixos.ops-fix = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.services.opsFix;
  in {
    options.services.opsFix = {
      enable = lib.mkEnableOption "allowlisted host action runner for Argus";
      containers = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = {};
        description = "Allowlisted container name -> owning host. Only these can be restarted.";
      };
      minIntervalSeconds = lib.mkOption {
        type = lib.types.int;
        default = 1800;
        description = "Minimum seconds between restarts of the same target.";
      };
    };

    config = lib.mkIf cfg.enable {
      # The allowlist is data, never derived from an alert payload.
      environment.etc."ops-fix/allowlist.json".text = builtins.toJSON {inherit (cfg) containers;};

      systemd.services.ops-fix-runner = {
        description = "Allowlisted host action runner (Argus)";
        wantedBy = ["multi-user.target"];
        after = ["network-online.target" "docker.service"];
        wants = ["network-online.target"];
        serviceConfig = {
          Type = "simple";
          User = "root";
          StateDirectory = "ops-fix";
          RuntimeDirectory = "ops-fix";
          Restart = "on-failure";
          RestartSec = 2;
          ExecStart = "${pkgs.python3}/bin/python3 ${./ops-fix/ops-fix-runner.py}";
        };
        environment = {
          OPS_FIX_SOCKET = "/run/ops-fix/ops.sock";
          OPS_FIX_ALLOWLIST = "/etc/ops-fix/allowlist.json";
          OPS_FIX_STATE = "/var/lib/ops-fix";
          OPS_FIX_MIN_INTERVAL = toString cfg.minIntervalSeconds;
          # System units get a minimal PATH; name the CLI explicitly.
          OPS_FIX_DOCKER = "${pkgs.docker}/bin/docker";
        };
      };
    };
  };
}
