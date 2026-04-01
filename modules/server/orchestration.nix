{config, ...}: let
  inherit (config) username;
in {
  flake.modules.nixos.orchestration = {
    pkgs,
    lib,
    config,
    ...
  }: {
    options.homelab.compose.stacks = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = ''
        Ordered list of compose stack names to auto-start on boot.
        Each name must correspond to a <name>.yml file in ~/homelab/.
        Services start sequentially in list order.
      '';
    };

    config = let
      composeDir = "/home/${username}/homelab";
      declaredStacks = config.homelab.compose.stacks;

      makeService = idx: name: {
        "podman-compose-${name}" = {
          Unit = {
            Description = "Podman compose stack: ${name}";
            After =
              ["network-online.target"]
              ++ (
                if idx == 0
                then []
                else ["podman-compose-${builtins.elemAt declaredStacks (idx - 1)}.service"]
              );
            Wants = ["network-online.target"];
          };
          Service = {
            Type = "oneshot";
            RemainAfterExit = true;
            WorkingDirectory = composeDir;
            # docker-compose standalone — "docker compose" (plugin) requires
            # CLI plugin search paths unavailable in minimal user session PATH.
            ExecStart = "/run/current-system/sw/bin/docker-compose -f ${composeDir}/${name}.yml up -d --remove-orphans";
            ExecStop = "/run/current-system/sw/bin/docker-compose -f ${composeDir}/${name}.yml stop";
            TimeoutStopSec = 60;
          };
          Install.WantedBy = ["default.target"];
        };
      };
    in {
      # Container orchestration defaults for server hosts.
      # Podman/dockerCompat is enabled by profile-base → containers module.

      # Linger: user session (and user services) survive after logout/reboot.
      # Required for rootless Podman compose stacks to auto-start on boot.
      users.users.${username}.linger = true;

      # docker-compose standalone binary for use in systemd user services.
      environment.systemPackages = [pkgs.docker-compose];

      # Generate one systemd user service per declared compose stack.
      home-manager.users.${username} = lib.mkIf (declaredStacks != []) {
        systemd.user.services =
          builtins.foldl' (acc: item: acc // item) {}
          (builtins.genList (idx: makeService idx (builtins.elemAt declaredStacks idx))
            (builtins.length declaredStacks));
      };
    };
  };
}
