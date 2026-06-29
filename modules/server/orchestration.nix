{config, ...}: let
  inherit (config) username;
in {
  flake.modules.nixos.orchestration = {
    pkgs,
    lib,
    config,
    ...
  }: {
    options.homelab.compose = {
      repoUrl = lib.mkOption {
        type = lib.types.str;
        default = "git@github_erikbpf:ErikBPF/servarr.git";
        description = "Git remote URL for the servarr compose repo.";
      };

      repoPath = lib.mkOption {
        type = lib.types.str;
        default = "/home/${username}/servarr";
        description = "Local clone path for the servarr repo.";
      };

      composeDir = lib.mkOption {
        type = lib.types.str;
        description = ''
          Path to the directory containing this host's compose yml files.
          Typically a subdirectory of repoPath, e.g. repoPath + "/machines/discovery".
        '';
      };

      stacks = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = ''
          Ordered list of compose stack names to auto-start on boot.
          Each name must correspond to a <name>.yml in composeDir.
          Services start sequentially in list order.
        '';
      };

      dockerSocket = lib.mkOption {
        type = lib.types.str;
        default = "unix:///run/user/1000/podman/podman.sock";
        description = ''
          Docker-compatible socket for docker-compose. Defaults to rootless
          Podman socket. Override to /run/docker.sock for rootful Docker.
        '';
      };

      defaultBranch = lib.mkOption {
        type = lib.types.str;
        default = "main";
        description = ''
          Branch servarr-pull syncs to when no per-host override is set.
          A feature-branch deploy is opt-in: `just pull-servarr <host> <branch>`
          writes a `.deploy-branch` pointer next to the clone; servarr-pull reads
          it (falling back to this default) and `reset --hard`s to origin/<branch>.
          The pointer is untracked so it survives reset --hard and persists across
          reboots until you `just pull-servarr <host>` (no branch ⇒ back to default).
        '';
      };
    };

    config = let
      cfg = config.homelab.compose;
      declaredStacks = cfg.stacks;

      makeService = idx: name: {
        "podman-compose-${name}" = {
          Unit = {
            Description = "Podman compose stack: ${name}";
            # After default.target (not network-online.target — that's a system
            # target and causes deadlocks during nixos-rebuild switch when
            # home-manager activation triggers user unit starts).
            After =
              ["default.target" "servarr-pull.service"]
              ++ (
                if idx == 0
                then []
                else ["podman-compose-${builtins.elemAt declaredStacks (idx - 1)}.service"]
              );
            Wants = ["servarr-pull.service"];
          };
          Service = {
            Type = "oneshot";
            RemainAfterExit = true;
            WorkingDirectory = cfg.composeDir;
            # Retry on failure — handles transient boot-time races
            # (e.g. homelab-net not ready, port conflicts with previous run).
            Restart = "on-failure";
            RestartSec = "30s";
            StartLimitBurst = 5;
            # Load .env so compose variable substitution works.
            EnvironmentFile = "-${cfg.composeDir}/.env";
            # Docker socket — rootless Podman by default, override for rootful Docker.
            Environment = "DOCKER_HOST=${cfg.dockerSocket}";
            ExecStart = "/run/current-system/sw/bin/docker-compose --project-name ${name} --env-file ${cfg.composeDir}/.env -f ${cfg.composeDir}/${name}.yml up -d --remove-orphans";
            ExecStop = "/run/current-system/sw/bin/docker-compose --project-name ${name} --env-file ${cfg.composeDir}/.env -f ${cfg.composeDir}/${name}.yml stop";
            TimeoutStopSec = 60;
          };
          # Empty WantedBy — these units are enabled (symlinked) but not pulled
          # in automatically by default.target during home-manager activation.
          # On boot they start via linger: systemd starts the user session which
          # activates default.target, which... does NOT pull these in.
          # Instead they are started explicitly by the servarr-pull service
          # ordering chain. This prevents nixos-rebuild switch from blocking
          # for minutes while compose stacks start.
          Install.WantedBy = ["default.target"];
        };
      };
    in
      lib.mkIf (declaredStacks != []) {
        # Linger: user session survives logout/reboot so user services
        # start on boot without an interactive login.
        users.users.${username}.linger = true;

        # docker-compose standalone binary (avoids CLI plugin path issues
        # in minimal systemd user session environments).
        environment.systemPackages = [pkgs.docker-compose pkgs.git];

        home-manager.users.${username} = {
          # Do not auto-start user services during nixos-rebuild switch.
          # Compose stacks take 1-10min to start — activating them during
          # home-manager activation causes the switch to appear hung.
          # They start correctly on the next boot via linger + default.target.
          systemd.user.startServices = false;

          systemd.user.services =
            # servarr-pull: clone or fast-forward the servarr repo before any
            # compose stack starts. Ensures compose files are always up to date
            # on boot. Uses the user's SSH key (inherited from the session).
            {
              servarr-pull = {
                Unit = {
                  Description = "Clone or pull servarr compose repo";
                  After = ["default.target"];
                };
                Service = {
                  Type = "oneshot";
                  RemainAfterExit = true;
                  ExecStart = let
                    script = pkgs.writeShellScript "servarr-pull" ''
                      set -euo pipefail
                      export PATH="${pkgs.openssh}/bin:${pkgs.git}/bin:${pkgs.sops}/bin:$PATH"
                      # Use the user SSH config for host aliases (github_erikbpf).
                      # No ssh-agent at this point — pass identity file directly.
                      export GIT_SSH_COMMAND="${pkgs.openssh}/bin/ssh -i /home/${username}/.ssh/id_ed25519 -o StrictHostKeyChecking=accept-new -F /home/${username}/.ssh/config"
                      REPO="${cfg.repoPath}"
                      MACHINE_DIR="${cfg.composeDir}"
                      # Target branch: a `.deploy-branch` pointer (written by
                      # `just pull-servarr <host> <branch>`) overrides the baked
                      # default. The pointer is untracked, so reset --hard below
                      # leaves it in place — a feature-branch deploy stays put
                      # across reboots until `just pull-servarr <host>` (no arg)
                      # rewrites it to the default. Trim whitespace; ignore empty.
                      BRANCH="${cfg.defaultBranch}"
                      if [ -s "$REPO/.deploy-branch" ]; then
                        PINNED="$(tr -d '[:space:]' < "$REPO/.deploy-branch")"
                        [ -n "$PINNED" ] && BRANCH="$PINNED"
                      fi
                      if [ ! -d "$REPO/.git" ]; then
                        ${pkgs.git}/bin/git clone ${cfg.repoUrl} "$REPO"
                      fi
                      # Authoritative sync: the host tree must match origin/$BRANCH
                      # regardless of local drift. The old `pull --ff-only || true`
                      # silently no-op'd once rsync (sync-servarr) dirtied the tree,
                      # so the host never received new commits (2026-06-29 incident).
                      # reset --hard makes git the single source→host path; rsync
                      # delivery is retired. Tracked config (compose files,
                      # AdGuardHome.yaml) is reset to origin — commit host config
                      # changes, don't hand-edit on the host. Untracked runtime
                      # state (.env, config/swag certs, adguard/work, caches, the
                      # .deploy-branch pointer) is left untouched. No `|| true`: a
                      # fetch/reset failure now fails the unit loudly instead of
                      # leaving the host silently stale.
                      echo "servarr-pull: syncing $REPO → origin/$BRANCH"
                      ${pkgs.git}/bin/git -C "$REPO" fetch --prune origin "$BRANCH"
                      ${pkgs.git}/bin/git -C "$REPO" reset --hard "origin/$BRANCH"
                      # Decrypt .env.sops → .env if stale or missing.
                      # --input-type/--output-type dotenv is required: sops
                      # uses file-extension auto-detection, and a `.env.sops`
                      # filename is read as JSON by default, which fails with
                      # "Could not unmarshal input data: invalid character '#'"
                      # because the encrypted file is dotenv-format (KEY=ENC).
                      # Without the explicit type, the redirect truncates .env
                      # to zero bytes and every compose stack loses its vars.
                      if [ -f "$MACHINE_DIR/.env.sops" ] && { [ ! -f "$MACHINE_DIR/.env" ] || [ "$MACHINE_DIR/.env.sops" -nt "$MACHINE_DIR/.env" ]; }; then
                        ${pkgs.sops}/bin/sops --input-type dotenv --output-type dotenv --decrypt "$MACHINE_DIR/.env.sops" > "$MACHINE_DIR/.env.new" \
                          && mv "$MACHINE_DIR/.env.new" "$MACHINE_DIR/.env"
                      fi
                      # Ensure homelab-net Docker/Podman network exists.
                      # Compose stacks declare it as external so it must be
                      # pre-created. Idempotent — no-op if already present.
                      DOCKER_HOST="${cfg.dockerSocket}" ${pkgs.docker}/bin/docker \
                        network create homelab-net 2>/dev/null || true
                    '';
                  in "${script}";
                };
                Install.WantedBy = ["default.target"];
              };
            }
            // builtins.foldl' (acc: item: acc // item) {}
            (builtins.genList (idx: makeService idx (builtins.elemAt declaredStacks idx))
              (builtins.length declaredStacks));
        };
      };
  };
}
