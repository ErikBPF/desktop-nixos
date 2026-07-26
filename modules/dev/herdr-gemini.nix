{inputs, ...}: {
  flake.modules.home.herdr-gemini = {
    config,
    lib,
    pkgs,
    ...
  }: let
    herdr = inputs.herdr.packages.${pkgs.stdenv.hostPlatform.system}.default;
    plusVersion = "0.1.20";
    navigatorVersion = "0.3.3";

    plusSource = pkgs.fetchurl {
      url = "https://github.com/cloudmanic/herdr-plus/archive/refs/tags/v${plusVersion}.tar.gz";
      hash = "sha256-2FEi9oG2UvsSPU92EHru7qHvbHjzRn3ZMSwjX6iF/pc=";
    };
    plusBinary = pkgs.fetchurl {
      url = "https://github.com/cloudmanic/herdr-plus/releases/download/v${plusVersion}/herdr-plus_${plusVersion}_linux_amd64.tar.gz";
      hash = "sha256-ic4zGjDwmgwEofwNoLNzISKDgZqszKl3zl5UrZmuM48=";
    };
    plus =
      pkgs.runCommand "herdr-plus-${plusVersion}" {
        nativeBuildInputs = [pkgs.gnutar pkgs.gzip];
      } ''
        mkdir -p source $out/bin
        tar -xzf ${plusSource} -C source --strip-components=1
        cp source/herdr-plugin.toml $out/herdr-plugin.toml
        tar -xzf ${plusBinary} -C $out/bin herdr-plus
        chmod +x $out/bin/herdr-plus
      '';

    navigatorArchive = pkgs.fetchurl {
      url = "https://github.com/thanhdat77/herdr-navigator/releases/download/v${navigatorVersion}/herdr-navigator-linux-x86_64.tar.gz";
      hash = "sha256-KdLB8PYXckXLksHLZfzmESxMd/nBNZi9n4CosYCFPgI=";
    };
    navigator =
      pkgs.runCommand "herdr-navigator-${navigatorVersion}" {
        nativeBuildInputs = [pkgs.gnutar pkgs.gzip];
      } ''
        mkdir -p unpack $out/target/release
        tar -xzf ${navigatorArchive} -C unpack
        cp unpack/herdr-navigator/herdr-plugin.toml $out/
        cp unpack/herdr-navigator/herdr-navigator $out/target/release/
        chmod +x $out/target/release/herdr-navigator
      '';

    project = {
      name,
      workingDir,
    }: {
      inherit name;
      working_dir = workingDir;
      tabs = [
        {
          name = "editor";
          command = "nvim .";
        }
        {
          name = "agents";
          panes = [
            {
              label = "Codex 1";
              command = "codex --yolo";
            }
            {
              label = "Codex 2";
              command = "codex --yolo";
              split = "right";
            }
            {
              label = "Codex 3";
              command = "codex --yolo";
              split = "down";
            }
            {
              label = "Codex 4";
              command = "codex --yolo";
              split = "right";
            }
          ];
        }
        {
          name = "terminals";
          panes = [
            {label = "Terminal 1";}
            {
              label = "Terminal 2";
              split = "right";
            }
          ];
        }
      ];
    };
    toml = pkgs.formats.toml {};
    defaults = {
      homelab = "~/Documents/erik/homelab";
      dataplatform = "~/Documents/nstech/dataplatform";
    };
    defaultSessions = ["homelab" "dataplatform"];

    bootstrap = pkgs.writeShellApplication {
      name = "herdr-bootstrap";
      runtimeInputs = [herdr pkgs.jq plus];
      text = ''
        session=$1
        project=$2
        export HERDR_SESSION="$session"

        for _ in {1..40}; do
          if workspaces=$(herdr workspace list 2>/dev/null); then
            if ! jq -e --arg label "$project" \
              'any(.result.workspaces[]?; .label == $label)' <<<"$workspaces" >/dev/null; then
              herdr-plus open "$project"
            fi
            exit
          fi
          sleep 0.25
        done
        echo "herdr session $session did not become ready" >&2
        exit 1
      '';
    };

    sessionService = name: {
      Unit = {
        Description = "Persistent Herdr session ${name}";
        After = ["network-online.target"];
        Wants = ["network-online.target"];
      };
      Service = {
        ExecStart = "${herdr}/bin/herdr --session ${name} server";
        ExecStartPost = "${bootstrap}/bin/herdr-bootstrap ${name} ${name}";
        Restart = "on-failure";
        RestartSec = 2;
      };
      Install.WantedBy = ["default.target"];
    };

    repoBootstrap = pkgs.writeShellApplication {
      name = "herdr-repo-bootstrap";
      runtimeInputs = [herdr pkgs.jq pkgs.systemd];
      text = ''
        session=$1
        remote_repo=$2
        remote_repo="''${remote_repo/#\~/$HOME}"
        systemctl --user enable --now "herdr-session@$session.service"
        export HERDR_SESSION="$session"
        for _ in {1..40}; do
          if workspaces=$(herdr workspace list 2>/dev/null); then
            if ! jq -e --arg label "$session" \
              'any(.result.workspaces[]?; .label == $label)' <<<"$workspaces" >/dev/null; then
              herdr workspace create --cwd "$remote_repo" --label "$session" --focus
            fi
            exit
          fi
          sleep 0.25
        done
        echo "herdr session $session did not become ready" >&2
        exit 1
      '';
    };
  in {
    home.packages = [plus navigator repoBootstrap];

    xdg.configFile = {
      "herdr/plugins/config/cloudmanic.herdr-plus/projects/homelab.toml".source = toml.generate "herdr-plus-homelab.toml" (project {
        name = "homelab";
        workingDir = defaults.homelab;
      });
      "herdr/plugins/config/cloudmanic.herdr-plus/projects/dataplatform.toml".source = toml.generate "herdr-plus-dataplatform.toml" (project {
        name = "dataplatform";
        workingDir = defaults.dataplatform;
      });
    };

    home.activation.linkHerdrPlugins = lib.hm.dag.entryAfter ["installPackages"] ''
      $DRY_RUN_CMD ${herdr}/bin/herdr plugin link ${plus}
      $DRY_RUN_CMD ${herdr}/bin/herdr plugin link ${navigator}
    '';

    systemd.user.services =
      builtins.listToAttrs (map (name: lib.nameValuePair "herdr-session-${name}" (sessionService name)) defaultSessions)
      // {
        "herdr-session@" = {
          Unit = {
            Description = "Persistent Herdr repository session %i";
            After = ["network-online.target"];
            Wants = ["network-online.target"];
          };
          Service = {
            ExecStart = "${herdr}/bin/herdr --session %i server";
            Restart = "on-failure";
            RestartSec = 2;
          };
        };
      };
  };
}
