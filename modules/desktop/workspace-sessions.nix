{
  config,
  inputs,
  ...
}: let
  flakeConfig = config;
in {
  config.flake.modules.nixos.desktop-workspaces = {
    users.users.${flakeConfig.username}.linger = true;
  };

  config.flake.modules.home.desktop-workspaces = {
    config,
    lib,
    pkgs,
    ...
  }: let
    herdr = inputs.herdr.packages.${pkgs.stdenv.hostPlatform.system}.default;
    projects = [
      {
        name = "dataplatform";
        directory = "${config.home.homeDirectory}/Documents/nstech/dataplatform";
        # Routing range for `launch shell|nvim|yazi` by active workspace.
        workspaces = lib.range 2 4;
        # Workspace that owns this project's eight window sessions.
        workspace = 2;
        prefix = "w";
        count = 8;
      }
      {
        name = "homelab";
        directory = "${config.home.homeDirectory}/Documents/erik/homelab";
        workspaces = lib.range 5 12;
        workspace = 7;
        prefix = "l";
        count = 8;
      }
    ];
    legacySessions = lib.concatMap (project:
      map (kind: {
        name = "${project.name}-${kind}";
        inherit (project) directory;
      }) ["code" "review"])
    projects;
    sessions = lib.concatMap (project:
      map (index: {
        name = "${project.prefix}${toString index}";
        inherit (project) directory workspace;
      }) (lib.range 1 project.count))
    projects;
    # Session state (scrollback, cwd, running programs, pane layout) is saved
    # here by tmux-resurrect and restored when desktop-tmux.service starts.
    resurrect = "${pkgs.tmuxPlugins.resurrect}/share/tmux-plugins/resurrect";
    resurrectDir = "${config.xdg.dataHome}/tmux/workspace-desktop";
    manifest = pkgs.writeText "desktop-workspaces.json" (builtins.toJSON {
      inherit projects resurrect resurrectDir;
      shell = "${pkgs.zsh}/bin/zsh";
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
    # User services need the setuid wrappers before profile/system binaries.
    servicePath = "/run/wrappers/bin:${config.home.profileDirectory}/bin:/run/current-system/sw/bin";
    stateRoot = project: "${config.xdg.stateHome}/opencode-v2-backends/${project.name}";
    passwordFile = project: "${stateRoot project}/server-password";
    legacyHomelabDatabase = "${config.xdg.dataHome}/opencode/opencode-homelab.db";
    backends =
      map (workspace: let
        project =
          workspace
          // (
            if workspace.name == "homelab"
            then {
              port = 4096;
              provider = "litellm";
              keyFile = "litellm_key";
              keyVariable = "OPENCODE_LITELLM_KEY";
            }
            else {
              port = 4097;
              provider = "work";
              keyFile = "work_key";
              keyVariable = "OPENCODE_WORK_KEY";
            }
          );
      in {
        inherit project;
        package = pkgs.writeShellApplication {
          name = "opencode-backend-${project.name}";
          runtimeInputs = [pkgs.coreutils];
          text = ''
            umask 077
            mkdir -p ${lib.escapeShellArg (stateRoot project)}
            if [[ ! -s ${lib.escapeShellArg (passwordFile project)} ]]; then
              ${pkgs.openssl}/bin/openssl rand -hex 32 > ${lib.escapeShellArg "${passwordFile project}.tmp"}
              mv ${lib.escapeShellArg "${passwordFile project}.tmp"} ${lib.escapeShellArg (passwordFile project)}
            fi
            OPENCODE_PASSWORD="$(<${lib.escapeShellArg (passwordFile project)})"
            export OPENCODE_PASSWORD
            unset OPENCODE_SERVER_PASSWORD OPENCODE_CONFIG OPENCODE_CONFIG_CONTENT
            unset OPENCODE_LITELLM_KEY OPENCODE_WORK_KEY
            export OPENCODE_CONFIG_DIR=${lib.escapeShellArg "${config.xdg.configHome}/opencode"}
            export OPENCODE_CONFIG_CONTENT=${lib.escapeShellArg (builtins.toJSON {
              model = "${project.provider}/deepseek-v4.1-flash";
              small_model = "${project.provider}/deepseek-v4.1-flash";
              default_agent = "build";
              experimental.policies = [
                {
                  action = "provider.use";
                  resource = "*";
                  effect = "deny";
                }
                {
                  action = "provider.use";
                  resource = project.provider;
                  effect = "allow";
                }
                {
                  action = "provider.use";
                  resource = "opencode-go";
                  effect = "allow";
                }
                {
                  action = "provider.use";
                  resource = "openai";
                  effect = "allow";
                }
              ];
            })}
            if [[ -r /run/secrets/opencode/${project.keyFile} ]]; then
              ${project.keyVariable}="$(</run/secrets/opencode/${project.keyFile})"
              export ${project.keyVariable}
            fi
            exec ${config.programs.opencode.package}/bin/opencode "$@"
          '';
        };
      })
      projects;
    inherit (lib.generators) mkLuaInline;
  in {
    # Permission-only repair: never create, open, or import the preserved V1 DB.
    home.activation.protectLegacyOpencodeHomelab = lib.hm.dag.entryAfter ["writeBoundary"] ''
      if [[ -f ${lib.escapeShellArg legacyHomelabDatabase} ]]; then
        run ${pkgs.coreutils}/bin/chmod 0600 -- ${lib.escapeShellArg legacyHomelabDatabase}
      fi
    '';

    home.packages =
      [coordinator]
      ++ map (backend: backend.package) backends
      ++ map ({project, ...}:
        pkgs.writeShellApplication {
          name =
            if project.name == "homelab"
            then "ol"
            else "ow";
          text = ''
            OPENCODE_PASSWORD="$(<${lib.escapeShellArg (passwordFile project)})"
            export OPENCODE_PASSWORD
            unset OPENCODE_SERVER_PASSWORD
            exec ${config.programs.opencode.package}/bin/opencode --server http://127.0.0.1:${toString project.port} ${lib.escapeShellArg project.directory} "$@"
          '';
        })
      backends;

    # Bare w1..w8 / l1..l8 attach this machine's persistent tmux session.
    # Reuses the same exact-name bootstrap the desktop windows use, so a
    # missing session is created (never a duplicate) before attaching.
    programs.zsh.shellAliases = lib.listToAttrs (map (session: {
        inherit (session) name;
        value = "${command} bootstrap ${session.name} && exec tmux -N -L workspace-desktop attach-session -t =${session.name}";
      })
      sessions);

    xdg.configFile."tmux/desktop-workspaces.conf".text = ''
      source-file "${config.xdg.configHome}/tmux/tmux.conf"
      set-option -s exit-empty off
      set-option -s exit-unattached off
      set-option -g destroy-unattached off
      set-option -g @resurrect-dir "${resurrectDir}"
      set-option -g @resurrect-processes '"nvim->nvim" ssh'
      run-shell "${resurrect}/resurrect.tmux"
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
            # Restore the last resurrect snapshot before any window unit's
            # bootstrap runs (a unit is only active once ExecStartPost exits).
            ExecStartPost = "-${command} restore";
            Environment = ["PATH=${servicePath}"];
            UnsetEnvironment = ["TMUX"];
            Restart = "on-failure";
            RestartSec = 2;
          };
        };
        tmux-save = {
          Unit.Description = "Save desktop tmux session state";
          Service = {
            Type = "oneshot";
            ExecStart = "${command} save";
          };
        };
        tmux-save-shutdown = {
          Unit = {
            Description = "Save desktop tmux session state before shutdown";
            DefaultDependencies = false;
            Before = ["shutdown.target"];
          };
          Service = {
            Type = "oneshot";
            ExecStart = "${command} save";
          };
          Install.WantedBy = ["shutdown.target"];
        };
      }
      // builtins.listToAttrs (map ({
        project,
        package,
      }:
        lib.nameValuePair "opencode-${project.name}" {
          Unit = {
            Description = "Persistent native OpenCode V2 backend for ${project.name}";
            # V2 caches config; HM symlink replacement must restart the backend.
            X-Restart-Triggers = ["${config.xdg.configFile."opencode/opencode.json".source}"];
          };
          Service = {
            # Foreground serve never registers/replaces the shared CLI service.
            ExecStart = "${package}/bin/opencode-backend-${project.name} serve --hostname 127.0.0.1 --port ${toString project.port}";
            WorkingDirectory = project.directory;
            Environment = [
              "OPENCODE_DISABLE_CLAUDE_CODE=1"
              "OPENCODE_DB=${config.xdg.dataHome}/opencode-v2-backends/${project.name}/opencode.db"
              "XDG_DATA_HOME=${config.xdg.dataHome}/opencode-v2-backends/${project.name}"
              "XDG_STATE_HOME=${stateRoot project}"
              "XDG_CACHE_HOME=${config.xdg.cacheHome}/opencode-v2-backends/${project.name}"
              "PATH=${servicePath}"
            ];
            Restart = "on-failure";
            RestartSec = 2;
            UMask = "0077";
          };
          Install.WantedBy = ["default.target"];
        })
      backends)
      // builtins.listToAttrs (map (session:
        lib.nameValuePair "desktop-session-${session.name}" {
          # Keep the previous servers alive until their work is explicitly retired.
          Unit = {
            Description = "Persistent local Herdr session ${session.name}";
            X-SwitchMethod = "keep-old";
          };
          Service = {
            ExecStart = "${herdr}/bin/herdr --session ${session.name} server";
            Environment = ["PATH=${servicePath}"];
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

    systemd.user.timers.tmux-save = {
      Unit.Description = "Periodically save desktop tmux session state";
      Timer = {
        OnStartupSec = "5min";
        OnUnitActiveSec = "5min";
        Unit = "tmux-save.service";
      };
      Install.WantedBy = ["timers.target"];
    };

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
