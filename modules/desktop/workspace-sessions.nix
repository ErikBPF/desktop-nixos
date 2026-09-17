{
  config,
  inputs,
  lib,
  ...
}: let
  flakeConfig = config;
in {
  options.defaultCodingAgent = lib.mkOption {
    type = lib.types.singleLineStr;
    default = "codex";
    description = "Installed executable used when creating local desktop coding sessions.";
  };

  config.flake.modules.nixos.desktop-workspaces = {
    users.users.${flakeConfig.username}.linger = true;
  };

  config.flake.modules.home.desktop-workspaces = {
    config,
    pkgs,
    ...
  }: let
    herdr = inputs.herdr.packages.${pkgs.stdenv.hostPlatform.system}.default;
    projects = [
      {
        name = "dataplatform";
        directory = "${config.home.homeDirectory}/Documents/nstech/dataplatform";
        workspaces = lib.range 2 4;
        code = 2;
        review = 3;
      }
      {
        name = "homelab";
        directory = "${config.home.homeDirectory}/Documents/erik/homelab";
        workspaces = lib.range 5 12;
        code = 7;
        review = 8;
      }
    ];
    legacySessions = lib.concatMap (project:
      map (kind: {
        name = "${project.name}-${kind}";
        inherit (project) directory;
        workspace = project.${kind};
      }) ["code" "review"])
    projects;
    sessions = lib.concatMap (project:
      map (suffix: {
        name = "${project.name}-${suffix}";
        inherit (project) directory;
        workspace =
          if builtins.elem suffix ["tuicr" "nvim"]
          then project.review
          else project.code;
      }) ((map (i: "agent-${toString i}") (lib.range 1 6)) ++ ["shell-1" "shell-2" "tuicr" "nvim"]))
    projects;
    manifest = pkgs.writeText "desktop-workspaces.json" (builtins.toJSON {
      inherit projects;
      shell = "${pkgs.zsh}/bin/zsh";
      inherit (flakeConfig) defaultCodingAgent;
    });
    coordinator = pkgs.writeShellApplication {
      name = "desktop-workspaces";
      runtimeInputs = [
        pkgs.tmux
        pkgs.python3
        pkgs.systemd
        config.programs.ghostty.package
        config.wayland.windowManager.hyprland.package
      ];
      text = ''
        exec python3 ${./_workspace-sessions.py} ${manifest} "$@"
      '';
    };
    command = "${coordinator}/bin/desktop-workspaces";
    inherit (lib.generators) mkLuaInline;
  in {
    home.packages = [
      coordinator
      (pkgs.writeShellApplication {
        name = "ol";
        text = ''
          exec ${config.home.profileDirectory}/bin/opencode-home attach http://127.0.0.1:4096 --dir ${config.home.homeDirectory}/Documents/erik/homelab "$@"
        '';
      })
      (pkgs.writeShellApplication {
        name = "ow";
        text = ''
          exec ${config.home.profileDirectory}/bin/opencode-work attach http://127.0.0.1:4097 --dir ${config.home.homeDirectory}/Documents/nstech/dataplatform "$@"
        '';
      })
    ];

    xdg.configFile."tmux/desktop-workspaces.conf".text = ''
      source-file "${config.xdg.configHome}/tmux/tmux.conf"
      set-option -s exit-empty off
      set-option -s exit-unattached off
      set-option -g destroy-unattached off
    '';

    systemd.user.services =
      {
        desktop-tmux = {
          Unit = {
            Description = "Persistent desktop tmux server";
            X-SwitchMethod = "keep-old";
          };
          Service = {
            ExecStart = "${pkgs.tmux}/bin/tmux -D -L workspace-desktop -f ${config.xdg.configHome}/tmux/desktop-workspaces.conf";
            Environment = ["PATH=${config.home.profileDirectory}/bin:/run/current-system/sw/bin"];
            UnsetEnvironment = ["TMUX"];
            Restart = "on-failure";
            RestartSec = 2;
          };
        };
      }
      // builtins.listToAttrs (map (project: let
        home = project.name == "homelab";
        profile = "opencode-${
          if home
          then "home"
          else "work"
        }";
        package = lib.findFirst (package: lib.getName package == profile) (throw "Missing ${profile} package") config.home.packages;
        port =
          if home
          then 4096
          else 4097;
      in
        lib.nameValuePair "opencode-${project.name}" {
          Unit.Description = "Persistent OpenCode backend for ${project.name}";
          Service = {
            ExecStart = "${package}/bin/${profile} serve --hostname 127.0.0.1 --port ${toString port}";
            WorkingDirectory = project.directory;
            Environment = ["PATH=${config.home.profileDirectory}/bin:/run/current-system/sw/bin"];
            Restart = "on-failure";
            RestartSec = 2;
          };
          Install.WantedBy = ["default.target"];
        })
      projects)
      // builtins.listToAttrs (map (session:
        lib.nameValuePair "desktop-session-${session.name}" {
          # Keep the previous servers alive until their work is explicitly retired.
          Unit = {
            Description = "Persistent local Herdr session ${session.name}";
            X-SwitchMethod = "keep-old";
          };
          Service = {
            ExecStart = "${herdr}/bin/herdr --session ${session.name} server";
            Environment = ["PATH=${config.home.profileDirectory}/bin:/run/current-system/sw/bin"];
            UnsetEnvironment = ["HERDR_STARTUP_CWD" "HERDR_SESSION" "HERDR_SOCKET_PATH"];
            Restart = "on-failure";
            RestartSec = 2;
          };
        })
      legacySessions)
      // builtins.listToAttrs (map (session:
        lib.nameValuePair "desktop-window-${session.name}" {
          Unit = {
            Description = "Desktop window for ${session.name}";
            Requires = ["desktop-tmux.service"];
            After = ["desktop-tmux.service"];
            PartOf = ["graphical-session.target"];
          };
          Service = {
            ExecStartPre = "${command} bootstrap ${session.name}";
            ExecStart = "${config.programs.ghostty.package}/bin/ghostty --gtk-single-instance=false --class=com.pastelariadev.${session.name} --title=${session.name} -e ${pkgs.tmux}/bin/tmux -N -L workspace-desktop attach-session -t =${session.name}";
            WorkingDirectory = session.directory;
            UnsetEnvironment = ["TMUX"];
            TimeoutStartSec = 240;
            Restart = "no";
          };
        })
      sessions);

    wayland.windowManager.hyprland.settings = {
      terminal = lib.mkForce {_var = "${command} launch shell";};
      terminalEditor = lib.mkForce {_var = "${command} launch nvim";};
      fileManagerTui = lib.mkForce {_var = "${command} launch yazi";};
      window_rule =
        map (session: {
          match.class = "^(com\\.pastelariadev\\.${session.name})$";
          workspace = "${toString session.workspace} silent";
        })
        sessions;
      on = [
        {
          _args = [
            "hyprland.start"
            (mkLuaInline ''function() hl.exec_cmd("${command} recover") end'')
          ];
        }
      ];
      bind = [
        {
          _args = [
            "SUPER + SHIFT + R"
            (mkLuaInline ''hl.dsp.exec_cmd("${command} recover")'')
          ];
        }
      ];
    };
  };
}
