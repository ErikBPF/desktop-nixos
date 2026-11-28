{config, ...}: let
  flakeConfig = config;
in {
  flake.modules.nixos.orion-strata-flash-next = {
    pkgs,
    lib,
    ...
  }: {
    home-manager.users.${flakeConfig.username}.systemd.user.services.strata-flash-next = {
      Unit = {
        Description = "Qwen3.8-Flash-Next Q2_0 on Strata";
        After = ["network-online.target"];
        Wants = ["network-online.target"];
      };
      Service = {
        Type = "simple";
        Restart = "always";
        RestartSec = "15s";
        LimitMEMLOCK = "infinity";
        ExecStartPre = "-${pkgs.podman}/bin/podman rm -f strata-flash-next";
        ExecStart = lib.concatStringsSep " " [
          "${pkgs.podman}/bin/podman run --rm --name strata-flash-next"
          "--network host"
          "--device /dev/kfd --device /dev/dri"
          "--group-add keep-groups"
          "-e HOME=/s/home -e STRATA_COMPONENTS_DIR=/s/components"
          "-e STRATA_MAX_TOP_LOGPROBS=160"
          "-v /opt/models:/models:ro"
          "-v /opt/models/strata:/s"
          "-w /s/terminal"
          "docker.io/rocm/dev-ubuntu-24.04:7.2.4-complete@sha256:92f309c51b52cef8762867848f1529dee821624f23cd5df38455e819538f762f"
          "./bin/strata serve --profile /s/home/.local/state/strata/launch/q2_0-120k.json"
          "--host ${flakeConfig.fleet.hosts.orion.tailscaleIp} --port 8080"
          "--parallel 2"
          "--output jsonl"
        ];
        ExecStop = "${pkgs.podman}/bin/podman stop strata-flash-next";
        TimeoutStopSec = "90s";
      };
      Install.WantedBy = ["default.target" "pqnld-decisions.service"];
    };
  };
}
