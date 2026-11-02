# Refresh generated files in the servarr tree before you commit. Today: mirror
# the canonical hermes SOUL.md (owned here) into the discovery stack so the
# deployed copy can't drift. Edit modules/hosts/discovery/homelab-SOUL.md, never
# the mirror. Run this, then commit + push in the servarr repo.
prep-servarr:
    #!/usr/bin/env bash
    set -euo pipefail
    SRC="$(readlink -f references/repos/servarr)"
    cp modules/hosts/discovery/homelab-SOUL.md \
       "$SRC/machines/discovery/config/hermes-agent/SOUL.md"
    echo ":: Mirrored homelab-SOUL.md → servarr/machines/discovery/config/hermes-agent/SOUL.md"
    echo ":: Now commit + push in the servarr repo, then: just pull-servarr <host>"

# Trigger a host to sync its servarr clone to a branch (fetch + reset --hard)
# and re-decrypt .env.sops. Run after committing + pushing servarr changes. The
# ref MUST exist on origin — the host resets to it; any local host edits are
# discarded by design (git is authoritative). Branch defaults to `main`; pass a
# feature branch to deploy it for testing, then `just pull-servarr <host>` (no
# branch) to return the host to main. The branch sticks across reboots via an
# untracked `.deploy-branch` pointer.
#   just pull-servarr discovery                 # → origin/main
#   just pull-servarr discovery feature/new-svc # → origin/feature/new-svc
pull-servarr target branch="main":
    #!/usr/bin/env bash
    set -euo pipefail
    target={{ quote(target) }}
    branch={{ quote(branch) }}
    [[ "$branch" =~ ^[A-Za-z0-9._/-]+$ ]] || { echo "BLOCKED: invalid branch" >&2; exit 2; }
    git check-ref-format --branch "$branch" >/dev/null || { echo "BLOCKED: invalid branch" >&2; exit 2; }
    IP="$(jq -er --arg h "$target" '.hosts[$h].tailscaleIp // .hosts[$h].ip' fleet.json)"
    echo ":: Pointing $target servarr clone at origin/$branch and pulling..."
    ssh -p 2222 erik@"$IP" bash -s -- "$branch" <<'REMOTE'
    set -euo pipefail
    branch="$1"
    repo=/home/erik/servarr
    test ! -e "$repo/.deploy-commit" || { echo 'BLOCKED: exact Servarr revision pin exists' >&2; exit 2; }
    printf '%s\n' "$branch" > "$repo/.deploy-branch"
    REMOTE
    # daemon-reload picks up a freshly-deployed unit; restart (not start) is
    # required because servarr-pull is RemainAfterExit — `start` no-ops once it
    # has run, so the reset --hard would never re-fire.
    ssh -p 2222 erik@"$IP" 'uid=$(id -u); sudo systemctl start user-runtime-dir@$uid.service user@$uid.service; export XDG_RUNTIME_DIR=/run/user/$uid; systemctl --user daemon-reload && systemctl --user restart servarr-pull.service'
    ssh -p 2222 erik@"$IP" 'export XDG_RUNTIME_DIR=/run/user/$(id -u); systemctl --user status servarr-pull.service --no-pager -n15'
    echo ":: $target now on origin/$branch. Recreate changed stacks: just kick-stack $target <stack>"

# Pin one host to an exact Servarr commit already published on origin/main.
pin-servarr target commit:
    #!/usr/bin/env bash
    set -euo pipefail
    target={{ quote(target) }}
    commit={{ quote(commit) }}
    [[ "$target" =~ ^[a-z0-9-]+$ ]] || { echo "BLOCKED: invalid host" >&2; exit 2; }
    [[ "$commit" =~ ^[0-9a-f]{40}$ ]] || { echo "BLOCKED: commit must be a full SHA-1" >&2; exit 2; }
    IP="$(jq -er --arg h "$target" '.hosts[$h].tailscaleIp // .hosts[$h].ip' fleet.json)"
    ssh -p 2222 erik@"$IP" bash -s -- "$commit" "$target" <<'REMOTE'
    set -euo pipefail
    commit="$1"
    target="$2"
    repo=/home/erik/servarr
    helper=$(readlink -f "$(command -v servarr-exact-revision)")
    case "$helper" in
      /nix/store/*/bin/servarr-exact-revision) ;;
      *) echo "BLOCKED: declarative servarr-exact-revision helper unavailable" >&2; exit 2 ;;
    esac
    "$helper" --help 2>&1 | grep -q pin-v2 || { echo "BLOCKED: deployed helper lacks pin-v2" >&2; exit 2; }
    flock -x /run/lock/servarr-repository.lock git -C "$repo" fetch --prune origin refs/heads/main:refs/remotes/origin/main
    "$helper" pin-v2 "$commit" "$target"
    uid=$(id -u)
    sudo -n /run/current-system/sw/bin/systemctl start "user-runtime-dir@$uid.service" "user@$uid.service"
    export XDG_RUNTIME_DIR="/run/user/$uid"
    systemctl --user daemon-reload
    systemctl --user restart servarr-pull.service
    systemctl --user status servarr-pull.service --no-pager -n15
    REMOTE

# Value-free exact-pin and runtime fingerprint for one Servarr rollout gate.
servarr-rollout-status target commit="":
    #!/usr/bin/env bash
    set -euo pipefail
    target={{ quote(target) }}
    commit={{ quote(commit) }}
    [[ "$target" =~ ^[a-z0-9-]+$ ]] || { echo "BLOCKED: invalid host" >&2; exit 2; }
    [[ -z "$commit" || "$commit" =~ ^[0-9a-f]{40}$ ]] || { echo "BLOCKED: commit must be a full SHA-1" >&2; exit 2; }
    IP="$(jq -er --arg h "$target" '.hosts[$h].tailscaleIp // .hosts[$h].ip' fleet.json)"
    ssh -p 2222 erik@"$IP" bash -s -- "$target" "$commit" <<'REMOTE'
    set -euo pipefail
    target="$1"
    expected="${2-}"
    repo=/home/erik/servarr
    die() { echo "BLOCKED: $*" >&2; exit 1; }
    helper="$(command -v servarr-exact-revision || true)"
    [[ -n "$helper" ]] || die "declarative exact-revision helper missing"
    helper="$(readlink -f "$helper")"
    case "$helper" in
      /nix/store/*/bin/servarr-exact-revision) ;;
      *) die "exact-revision helper is not declarative" ;;
    esac
    "$helper" --help 2>&1 | grep -q pin-v2 || die "deployed helper lacks pin-v2"
    head="$(git -C "$repo" rev-parse HEAD)"
    tree="$(git -C "$repo" show -s --format=%T HEAD)"
    pin_state=absent
    if [[ -e "$repo/.deploy-commit" ]]; then
      jq -e --arg machine "$target" '
        (keys | sort) == ["pin", "pin_sha256"] and
        (.pin | keys | sort) == ["commit", "machine", "tree", "version"] and
        .pin.version == 2 and .pin.machine == $machine and
        (.pin.commit | test("^[0-9a-f]{40}$")) and
        (.pin.tree | test("^[0-9a-f]{40}$")) and
        (.pin_sha256 | test("^[0-9a-f]{64}$"))
      ' "$repo/.deploy-commit" >/dev/null || die "malformed v2 pin"
      pin_sha="$(jq -jcS .pin "$repo/.deploy-commit" | sha256sum | cut -d' ' -f1)"
      [[ "$pin_sha" == "$(jq -r .pin_sha256 "$repo/.deploy-commit")" ]] || die "pin hash mismatch"
      [[ "$head" == "$(jq -r .pin.commit "$repo/.deploy-commit")" ]] || die "pin HEAD mismatch"
      [[ "$tree" == "$(jq -r .pin.tree "$repo/.deploy-commit")" ]] || die "pin tree mismatch"
      [[ -z "$expected" || "$head" == "$expected" ]] || die "unexpected exact pin"
      pin_state=v2
    else
      [[ -z "$expected" ]] || die "expected exact pin missing"
    fi
    export XDG_RUNTIME_DIR="/run/user/$(id -u)"
    systemctl --user is-active servarr-pull.service >/dev/null || die "servarr-pull inactive"
    case "$target" in
      kepler) stacks=(infra buzz monitoring sync security) ;;
      orion) stacks=(shared monitoring ai-models sync retrieval) ;;
      voyager) stacks=(offsite) ;;
      *) die "host outside exact-pin rollout" ;;
    esac
    runtime="$(mktemp)"
    trap 'rm -f "$runtime"' EXIT
    container_count=0
    for stack in "${stacks[@]}"; do
      unit="podman-compose-$stack.service"
      systemctl --user is-enabled "$unit" >/dev/null || die "rollout unit disabled: $unit"
      systemctl --user is-active "$unit" >/dev/null || die "rollout unit inactive: $unit"
      mapfile -t ids < <(docker ps -aq \
        --filter "label=com.docker.compose.project=$stack" | sort)
      ((${#ids[@]} > 0)) || die "rollout stack has no containers: $stack"
      for id in "${ids[@]}"; do
        record="$(docker inspect -- "$id" | jq -cer '
          .[0] | {
            name: (.Name | ltrimstr("/")),
            state: (.State.Status + "/" + (.State.Health.Status // "none") + "/" + (.State.ExitCode | tostring)),
            fingerprint: [.Id, .Name, .Config.Labels["com.docker.compose.project"], .State.StartedAt]
          }
        ')"
        container_key="$(jq -r '.name + "/" + .state' <<<"$record")"
        case "$container_key" in
          */running/healthy/0|*/running/none/0|buzz-minio-init/exited/none/0|restic-rest-init/exited/none/0) ;;
          *) die "rollout container unhealthy" ;;
        esac
        jq -r '.fingerprint | @tsv' <<<"$record" >>"$runtime"
        ((container_count += 1))
      done
    done
    docker network inspect homelab-net >/dev/null || die "homelab-net missing"
    runtime_sha256="$(sort "$runtime" | sha256sum | cut -d' ' -f1)"
    printf 'target=%s pin=%s head=%s tree=%s units=%s containers=%s runtime_sha256=%s\n' \
      "$target" "$pin_state" "$head" "$tree" "${#stacks[@]}" "$container_count" "$runtime_sha256"
    REMOTE

# Repair only the Git checkout surface; leave untracked container runtime state alone.
repair-servarr-checkout target:
    #!/usr/bin/env bash
    set -euo pipefail
    IP="$(just _host-ip {{target}})"
    ssh -p 2222 erik@"$IP" 'sudo -n bash -s' <<'REMOTE'
    set -euo pipefail
    repo=/home/erik/servarr
    test -d "$repo/.git"
    while IFS= read -r -d '' relative; do
      path="$repo/$relative"
      [[ -e "$path" || -L "$path" ]] && chown --no-dereference erik:users "$path"
      parent=$(dirname "$path")
      while test "$parent" != "$repo"; do
        chown --no-dereference erik:users "$parent"
        parent=$(dirname "$parent")
      done
    done < <(git -c safe.directory="$repo" -C "$repo" ls-files -z)
    chown -R erik:users "$repo/.git"
    echo "servarr_checkout=ownership_repaired"
    REMOTE

# Delegate Harbor robot provisioning to Servarr; token stays in the pipe.
provision-airflow-harbor-pull-robot:
    #!/usr/bin/env bash
    set -euo pipefail
    token=$(sops --decrypt --extract '["vault_root_token"]' secrets/sops/secrets.yaml)
    printf '%s\n' "$token" | ssh -p 2222 erik@{{ip_discovery}} \
      'cd /home/erik/servarr && just provision-airflow-harbor-pull-robot'
    unset token

# Diagnose the per-user manager required by servarr-pull and compose units.
diagnose-servarr-user target:
    #!/usr/bin/env bash
    set -euo pipefail
    IP="$(just _host-ip {{target}})"
    ssh -p 2222 erik@"$IP" 'sudo systemctl status systemd-logind.service user-runtime-dir@$(id -u).service user@$(id -u).service --no-pager -n20 || true; sudo journalctl -u systemd-logind.service -u user-runtime-dir@$(id -u).service -u user@$(id -u).service --no-pager -n30'

# Recover a user manager after logind loses its PID1 transport across reboot.
repair-servarr-user target:
    #!/usr/bin/env bash
    set -euo pipefail
    IP="$(just _host-ip {{target}})"
    ssh -p 2222 erik@"$IP" 'uid=$(id -u); sudo systemctl restart systemd-logind.service; sudo systemctl restart user-runtime-dir@$uid.service; sudo systemctl start user@$uid.service; export XDG_RUNTIME_DIR=/run/user/$uid; state=$(systemctl --user is-system-running 2>/dev/null || true); printf "user-manager=%s\n" "$state"; case "$state" in starting|running|degraded) ;; *) exit 1;; esac'

# Run the sister repo's database backup on a deployed servarr host and prove
# the LiteLLM dump is non-empty and gzip-valid before a control-plane cutoff.
backup-servarr-db target:
    #!/usr/bin/env bash
    set -euo pipefail
    IP="$(just _host-ip {{target}})"
    ssh -p 2222 erik@"$IP" '
      set -euo pipefail
      cd /home/erik/servarr/machines/{{target}}
      backup="backups/postgres/$(date +%Y-%m-%d_%H%M%S)"
      mkdir -p "$backup"
      user=$(sed -n "s/^POSTGRES_USER=//p" .env | tail -1)
      test -n "$user"
      docker exec postgres pg_dump -U "$user" litellm | gzip > "$backup/litellm.sql.gz"
      latest=$(find backups/postgres -mindepth 1 -maxdepth 1 -type d -printf "%T@ %p\n" | sort -nr | head -1 | cut -d" " -f2-)
      test -n "$latest"
      test -s "$latest/litellm.sql.gz"
      gzip -t "$latest/litellm.sql.gz"
      printf ":: verified LiteLLM DB backup: %s/litellm.sql.gz\n" "$latest"
    '

# One-time no-clobber cutover from the tracked live AdGuard YAML to the
# gitignored runtime bind. The migration helper is read from the exact reviewed
# Servarr commit and runs before pull-servarr can reset the legacy tracked file.
discovery-servarr-status-value-free:
    #!/usr/bin/env bash
    set -euo pipefail
    IP="$(just _host-ip discovery)"
    ssh -p 2222 erik@"$IP" 'git -C /home/erik/servarr status --short --branch --untracked-files=no'

discovery-servarr-pull-diagnostic:
    #!/usr/bin/env bash
    set -euo pipefail
    IP="$(just _host-ip discovery)"
    ssh -p 2222 erik@"$IP" 'systemctl --user --no-pager --full status servarr-pull.service || true; journalctl --user -u servarr-pull.service -n 30 --no-pager'
