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
    base = config.programs.opencode.settings;
    # Three-level agent framework: L1 plans, L2 coordinates a slice, L3 executes.
    # Backend profiles replace the plain build agent with this hierarchy.
    threeLevelPlugin = ../dev/opencode-plugins-v2/three-level;
    planning = [
      {
        action = "edit";
        resource = "*";
        effect = "deny";
      }
      {
        action = "edit";
        resource = "docs/*";
        effect = "ask";
      }
    ];
    protected = builtins.filter (rule: rule.effect == "deny") base.permissions;
    mkProfile = project: let
      model = "${project.provider}/deepseek-v4.1-flash";
      # Work's OpenRouter route rejects reasoning_effort and exposes no variants.
      variant = name:
        if project.variants
        then "#${name}"
        else "";
      agents = {
        pilot-l1 = {
          mode = "primary";
          model = "${model}${variant "max"}";
          description = "L1 orchestrator: program plan, independent slice coordinators and resources.";
          system = ''
            You are L1, the program orchestrator. Keep the main plan, resource budgets,
            dependencies and final status. Use dispatch_slice to assign concrete slices
            to independent L2 sessions. Supply scope, acceptance criteria, relevant
            paths, resource limits and the expected report location. Independent slices
            may run concurrently; do not assign overlapping writers.
            Completion notices return to you while this instance runs. After restarting,
            inspect previously returned session IDs with slice_status before redispatching.
            Delegate implementation. Read the project's env_config.yaml and compute
            inventory when present. Hardware totals are not available resource grants.
            Use the repository's coordination templates. Summarize accepted outcomes,
            verification, unresolved decisions and blockers; never manufacture evidence.
          '';
          permissions =
            planning
            ++ [
              {
                action = "shell";
                resource = "*";
                effect = "deny";
              }
              {
                action = "subagent";
                resource = "*";
                effect = "deny";
              }
              {
                action = "dispatch_slice";
                resource = "*";
                effect = "allow";
              }
              {
                action = "slice_status";
                resource = "*";
                effect = "allow";
              }
            ]
            ++ protected;
        };
        pilot-l2 = {
          mode = "primary";
          model = "${model}${variant "high"}";
          description = "L2 slice coordinator: PL/IP/RV, task acceptance and delegated execution.";
          system = ''
            You are L2, an independent slice coordinator. Own the /pl -> /ip -> /rv
            workflow and canonical task ledger. Read source and run verification as
            needed, but delegate implementation to native subagent pilot-l3.
            Define dependencies and parallel tasks before dispatch. Include paths,
            concrete acceptance criteria and resource limits in every handover.
            Accept exact result revisions before dependent work. After rejection,
            dispatch a fresh fixer; obtain a fresh pilot-l3 whole-slice review before
            final acceptance. Keep the slice one-pager current. Your final report must
            state outcome, changed files, verification evidence, decisions, remaining
            work and blockers. A tool returning is not proof of accepted work.
          '';
          permissions =
            planning
            ++ [
              {
                action = "subagent";
                resource = "*";
                effect = "deny";
              }
              {
                action = "subagent";
                resource = "pilot-l3";
                effect = "allow";
              }
              {
                action = "dispatch_slice";
                resource = "*";
                effect = "deny";
              }
              {
                action = "slice_status";
                resource = "*";
                effect = "deny";
              }
            ]
            ++ protected;
        };
        pilot-l3 = {
          mode = "subagent";
          model = "${model}${variant "high"}";
          description = "L3 task executor or fresh reviewer; reports to its slice coordinator.";
          system = ''
            Execute only your assigned task and paths. Follow repository instructions
            and its verification recipes. For review assignments, inspect the complete
            slice and downstream effects without editing implementation. Report exact
            changed files, commands/results, assumptions and blockers to L2. Never
            claim a test or deployment ran without evidence. Do not create more agents
            or allocate remote compute beyond the grant in your handover.
          '';
          permissions = [
            {
              action = "subagent";
              resource = "*";
              effect = "deny";
            }
            {
              action = "dispatch_slice";
              resource = "*";
              effect = "deny";
            }
            {
              action = "slice_status";
              resource = "*";
              effect = "deny";
            }
          ];
        };
      };
    in
      builtins.removeAttrs base ["agent" "agents" "default_agent" "model" "small_model"]
      // {
        model = model;
        small_model = model;
        default_agent = "pilot-l1";
        inherit agents;
        plugins = base.plugins ++ ["file://${threeLevelPlugin}"];
        skills = ["${config.home.homeDirectory}/.agents/skills"];
        experimental =
          base.experimental
          // {
            policies =
              builtins.filter (rule: rule.action != "provider.use") base.experimental.policies
              ++ [
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
          };
      };
    routedProjects =
      map (workspace:
        workspace
        // (
          if workspace.name == "homelab"
          then {
            port = 4096;
            provider = "litellm";
            keyFile = "litellm_key";
            keyVariable = "OPENCODE_LITELLM_KEY";
            variants = true;
          }
          else {
            port = 4097;
            provider = "work";
            keyFile = "work_key";
            keyVariable = "OPENCODE_WORK_KEY";
            variants = false;
          }
        ))
      projects;
    profiles =
      builtins.listToAttrs (map (project: {
          name = project.name;
          value = mkProfile project;
        })
        routedProjects);
    profileFile = project:
      pkgs.writeText "opencode-three-level-${project.name}.json"
      (builtins.toJSON profiles.${project.name});
    backends =
      map (project: {
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
            export OPENCODE_CONFIG=${lib.escapeShellArg (profileFile project)}
            export OPENCODE_THREE_LEVEL_L2_MODEL=${lib.escapeShellArg profiles.${project.name}.agents.pilot-l2.model}
            if [[ -r /run/secrets/opencode/${project.keyFile} ]]; then
              ${project.keyVariable}="$(</run/secrets/opencode/${project.keyFile})"
              export ${project.keyVariable}
            fi
            exec ${config.programs.opencode.package}/bin/opencode "$@"
          '';
        };
      })
      routedProjects;
    inherit (lib.generators) mkLuaInline;
    retireLegacyRtk = pkgs.writeShellScript "retire-legacy-opencode-rtk" ''
      set -euo pipefail
      legacy=${lib.escapeShellArg "${config.xdg.configHome}/opencode/plugins/rtk.ts"}
      backup=${lib.escapeShellArg "${config.xdg.stateHome}/opencode-v2-migration/rtk-v1.ts"}
      [[ -L "$legacy" && -f "$legacy" ]] || exit 0
      case "$(${pkgs.coreutils}/bin/readlink -f -- "$legacy")" in
        /nix/store/*) ;;
        *) exit 0 ;;
      esac
      # Retire only the verified HM-owned V1 RTK copy; preserve custom files.
      [[ "$(${pkgs.coreutils}/bin/sha256sum "$legacy" | ${pkgs.coreutils}/bin/cut -d ' ' -f 1)" == 6530c131946c84892f9522abd68d4e513e1e658d8ddbad1f59388c86ebbcb6bb ]] || exit 0
      [[ ! -L "$backup" ]] || exit 0
      if [[ ! -e "$backup" ]]; then
        ${pkgs.coreutils}/bin/install -D -m 0600 -- "$legacy" "$backup"
      fi
      [[ "$(${pkgs.coreutils}/bin/stat -c %a -- "$backup")" == 600 ]] || exit 0
      [[ -f "$backup" ]] && ${pkgs.diffutils}/bin/cmp -s -- "$legacy" "$backup" || exit 0
      ${pkgs.coreutils}/bin/unlink -- "$legacy"
    '';
  in {
    # Inspectable projection of the generated backend profiles (tests and ops).
    options.programs.opencode-backends.profiles = lib.mkOption {
      type = lib.types.attrsOf lib.types.raw;
      default = {};
      description = "Generated three-level OpenCode profiles per workspace backend.";
    };
    config = {
      programs.opencode-backends.profiles = profiles;
      # Permission-only repair: never create, open, or import the preserved V1 DB.
    home.activation.protectLegacyOpencodeHomelab = lib.hm.dag.entryAfter ["writeBoundary"] ''
      if [[ -f ${lib.escapeShellArg legacyHomelabDatabase} ]]; then
        run ${pkgs.coreutils}/bin/chmod 0600 -- ${lib.escapeShellArg legacyHomelabDatabase}
      fi
    '';
    home.activation.retireLegacyOpencodeRtk = lib.hm.dag.entryBetween ["reloadSystemd"] ["writeBoundary"] ''
      run ${retireLegacyRtk}
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
            X-Restart-Triggers = ["${config.xdg.configFile."opencode/opencode.json".source}" "${retireLegacyRtk}"];
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
  };
}
