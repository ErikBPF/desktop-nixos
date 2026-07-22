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

      vaultEnvStacks = lib.mkOption {
        type = lib.types.attrsOf (lib.types.listOf lib.types.str);
        default = {};
        example = lib.literalExpression ''
          {
            tunneling = [ "tunneling" ];
            "ai-serving" = [ "ai-serving" "shared-db" ];
          }
        '';
        description = ''
          Stacks whose secrets are sourced from OpenBao via vault-agent (P3.3).
          Maps a stack name to the list of vault-agent env-file basenames it
          consumes (each at `/run/vault-agent/<basename>.env`, rendered by the
          discovery vault-agent). compose gets a `--env-file` for each, layered
          after the sops .env so Vault wins. A stack lists its own
          `<stack>.env` (stack-local secrets) plus any shared renders like
          `shared-db` (POSTGRES/REDIS). The compose yml keeps its existing
          interpolation; only the values' origin moves. Migrated keys are removed
          from .env.sops once verified.
        '';
      };

      secretSpecRuntimeProfiles = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = {};
        description = ''
          Stack-to-profile map for approved SecretSpec runtime boundaries. The
          matching vault-agent env basename is resolved by SecretSpec and is not
          also passed directly to Compose.
        '';
      };

      secretSpecRuntimeHealthContainers = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = {};
        description = ''
          Stack-to-container map for targeted post-start health gates on
          SecretSpec runtime boundaries.
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
          An exact `.deploy-commit` pin takes precedence and is activated
          without network access; malformed or unavailable pins fail closed.
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
      servarrExactRevision = pkgs.writeShellApplication {
        name = "servarr-exact-revision";
        runtimeInputs = with pkgs; [docker-compose git python3 sops];
        text = ''
          exec python3 ${./_servarr-exact-revision.py} "$@"
        '';
      };

      # Stacks in vaultEnvStacks get one --env-file per listed vault-agent render,
      # layered after the sops .env (later --env-file wins for overlapping keys).
      makeService = idx: name: let
        secretSpecProfile = cfg.secretSpecRuntimeProfiles.${name} or null;
        secretSpecHealthContainer = cfg.secretSpecRuntimeHealthContainers.${name} or null;
        secretSpecEnv =
          if secretSpecProfile == null
          then name
          else secretSpecProfile;
        vaultBasenames = cfg.vaultEnvStacks.${name} or [];
        vaultEnvFlags =
          lib.concatMapStrings (b: " --env-file /run/vault-agent/${b}.env")
          (lib.filter (b: b != secretSpecProfile) vaultBasenames);
        secretSpecPrefix = lib.optionalString (secretSpecProfile != null) "${pkgs.secretspec}/bin/secretspec run --file ${cfg.composeDir}/secretspec.toml --profile ${secretSpecEnv} --provider dotenv:/run/vault-agent/${secretSpecEnv}.env --reason discovery-${name}-production-runtime -- ";
        secretSpecPreflight = pkgs.writeShellScript "secretspec-${name}-preflight" ''
          set -euo pipefail
          ${pkgs.systemd}/bin/systemctl is-active vault-agent.service >/dev/null
          render=/run/vault-agent/${secretSpecEnv}.env
          [ "$(${pkgs.coreutils}/bin/stat -c '%a %U %G' "$render")" = "440 root docker" ]
          ${pkgs.coreutils}/bin/head -c0 "$render"
        '';
        secretSpecHealthGate =
          if secretSpecHealthContainer == null
          then null
          else
            pkgs.writeShellScript "secretspec-${name}-health" ''
              set -euo pipefail
              health_container="${secretSpecHealthContainer}"
              for _ in $(${pkgs.coreutils}/bin/seq 1 60); do
                status="$(${pkgs.docker}/bin/docker inspect --format '{{.State.Health.Status}}' "$health_container" 2>/dev/null || true)"
                [ "$status" = healthy ] && exit 0
                [ "$status" = unhealthy ] && exit 1
                ${pkgs.coreutils}/bin/sleep 2
              done
              exit 1
            '';
      in {
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
            ExecStartPre = lib.optional (secretSpecProfile != null) secretSpecPreflight;
            ExecStart = "${secretSpecPrefix}/run/current-system/sw/bin/docker-compose --project-name ${name} --env-file ${cfg.composeDir}/.env${vaultEnvFlags} -f ${cfg.composeDir}/${name}.yml up -d --remove-orphans";
            ExecStartPost = lib.optional (secretSpecHealthContainer != null) secretSpecHealthGate;
            ExecStop = "${secretSpecPrefix}/run/current-system/sw/bin/docker-compose --project-name ${name} --env-file ${cfg.composeDir}/.env${vaultEnvFlags} -f ${cfg.composeDir}/${name}.yml stop";
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
        environment.systemPackages = [pkgs.docker-compose pkgs.git servarrExactRevision];
        systemd.tmpfiles.rules = [
          "f /run/lock/servarr-repository.lock 0660 root users - -"
        ];

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
                      LOCK="/run/lock/servarr-repository.lock"
                      exec 9>"$LOCK"
                      ${pkgs.util-linux}/bin/flock 9
                      # Target branch: a `.deploy-branch` pointer (written by
                      # `just pull-servarr <host> <branch>`) overrides the baked
                      # default. The pointer is untracked, so reset --hard below
                      # leaves it in place — a feature-branch deploy stays put
                      # across reboots until `just pull-servarr <host>` (no arg)
                      # rewrites it to the default. Trim whitespace; ignore empty.
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
                      if [ -e "$REPO/.deploy-commit" ]; then
                        [ -f "$REPO/.deploy-commit" ] || { echo "servarr-pull: exact revision pin is not a regular file" >&2; exit 1; }
                        ${pkgs.jq}/bin/jq -e '
                          (keys | sort) == ["pin", "pin_sha256"] and
                          (.pin | keys | sort) == ["commit", "render_sha256", "selection", "tree", "version"] and
                          .pin.version == 1 and
                          (.pin.commit | test("^[0-9a-f]{40}$")) and
                          (.pin.tree | test("^[0-9a-f]{40}$")) and
                          (.pin.render_sha256 | test("^[0-9a-f]{64}$")) and
                          (.pin.selection == "forward" or .pin.selection == "rollback") and
                          (.pin_sha256 | test("^[0-9a-f]{64}$"))
                        ' "$REPO/.deploy-commit" >/dev/null || { echo "servarr-pull: malformed exact revision pin" >&2; exit 1; }
                        PINNED_COMMIT="$(${pkgs.jq}/bin/jq -r .pin.commit "$REPO/.deploy-commit")"
                        PINNED_TREE="$(${pkgs.jq}/bin/jq -r .pin.tree "$REPO/.deploy-commit")"
                        PINNED_RENDER="$(${pkgs.jq}/bin/jq -r .pin.render_sha256 "$REPO/.deploy-commit")"
                        PINNED_SHA="$(${pkgs.jq}/bin/jq -r .pin_sha256 "$REPO/.deploy-commit")"
                        ACTUAL_PIN_SHA="$(${pkgs.jq}/bin/jq -jcS .pin "$REPO/.deploy-commit" | ${pkgs.coreutils}/bin/sha256sum | cut -d' ' -f1)"
                        [ "$ACTUAL_PIN_SHA" = "$PINNED_SHA" ] || { echo "servarr-pull: exact revision pin hash differs" >&2; exit 1; }
                        ${pkgs.git}/bin/git -C "$REPO" cat-file -e "$PINNED_COMMIT^{commit}" || { echo "servarr-pull: exact revision object absent" >&2; exit 1; }
                        [ "$(${pkgs.git}/bin/git -C "$REPO" show -s --format=%T "$PINNED_COMMIT")" = "$PINNED_TREE" ] || { echo "servarr-pull: exact revision tree differs" >&2; exit 1; }
                        echo "servarr-pull: activating prefetched exact revision"
                        ${pkgs.git}/bin/git -C "$REPO" reset --hard "$PINNED_COMMIT"
                        [ "$(${pkgs.git}/bin/git -C "$REPO" rev-parse HEAD)" = "$PINNED_COMMIT" ] || { echo "servarr-pull: exact revision activation differs" >&2; exit 1; }
                        EXACT_PIN_ACTIVE=1
                      else
                        EXACT_PIN_ACTIVE=0
                        BRANCH="${cfg.defaultBranch}"
                        if [ -s "$REPO/.deploy-branch" ]; then
                          PINNED="$(tr -d '[:space:]' < "$REPO/.deploy-branch")"
                          [ -n "$PINNED" ] && BRANCH="$PINNED"
                        fi
                        echo "servarr-pull: syncing $REPO → origin/$BRANCH"
                        ${pkgs.git}/bin/git -C "$REPO" fetch --prune origin "$BRANCH"
                        ${pkgs.git}/bin/git -C "$REPO" reset --hard "origin/$BRANCH"
                      fi
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
                      if [ "$EXACT_PIN_ACTIVE" -eq 1 ]; then
                        ACTUAL_RENDER="$(${pkgs.docker-compose}/bin/docker-compose \
                          --project-name networking --project-directory "$MACHINE_DIR" \
                          --env-file "$MACHINE_DIR/.env" --env-file /run/vault-agent/networking.env \
                          -f "$MACHINE_DIR/networking.yml" config --no-interpolate --no-env-resolution \
                          | ${pkgs.coreutils}/bin/sha256sum | cut -d' ' -f1)"
                        [ "$ACTUAL_RENDER" = "$PINNED_RENDER" ] || { echo "servarr-pull: exact revision render differs" >&2; exit 1; }
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
