# Regenerate fleet.json from the flake SSOT (modules/meta.nix). Run after editing
# fleet.hosts; commit the result. Consumers (justfile ip_*, homelab-iac) read it.
fleet-json:
    nix eval .#fleet --json | jq . > fleet.json
    @echo ":: fleet.json regenerated — review the diff and commit"

# Fail if fleet.json is stale vs the flake (drift guard for `just check` / CI).
fleet-check:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! diff -u fleet.json <(nix eval .#fleet --json | jq .) >/dev/null; then
        echo ":: fleet-check FAILED — fleet.json is stale; run: just fleet-json" >&2
        exit 1
    fi
    echo ":: fleet-check OK — fleet.json matches the flake"

# Fleet nixpkgs drift at a glance: each host's BOOTED nixpkgs short-rev vs the
# flake's target (the root `nixpkgs` input in flake.lock — the rev a `switch`
# would build). DRIFT = host is behind/ahead of the flake. Reaches hosts over the
# tailnet (tailscaleIp, works roaming); Endeavour is read locally; homeassistant
# (HAOS, not NixOS) is skipped. Makes P5 drift a command, not a memory file
# (docs/proposals/2026-07-12-fleet-upgrade-hardening.md).
fleet-status:
    #!/usr/bin/env bash
    set -uo pipefail
    target=$(jq -r '.nodes[.nodes.root.inputs.nixpkgs].locked.rev' flake.lock | cut -c1-7)
    revof() { local v="${1%% *}"; echo "${v##*.}"; }
    row() { printf '%-12s %-12s %-9s %s\n' "$1" "$2" "$target" "$3"; }
    printf '%-12s %-12s %-9s %s\n' HOST BOOTED TARGET STATE
    b=$(revof "$(nixos-version)")
    row endeavour "$b" "$([ "$b" = "$target" ] && echo OK || echo DRIFT)"
    for h in $(jq -r '.hosts | keys[] | select(. != "endeavour" and . != "homeassistant")' fleet.json); do
        addr=$(jq -r --arg h "$h" '.hosts[$h].tailscaleIp // empty' fleet.json)
        [ -z "$addr" ] && { row "$h" "no-tsip" "SKIP"; continue; }
        out=$(timeout 10 ssh -p 2222 -o ConnectTimeout=6 -o BatchMode=yes -o StrictHostKeyChecking=accept-new "erik@$addr" nixos-version 2>/dev/null || true)
        if [ -z "$out" ]; then
            row "$h" "unreachable" "—"
        else
            b=$(revof "$out")
            row "$h" "$b" "$([ "$b" = "$target" ] && echo OK || echo DRIFT)"
        fi
    done

build target=profile:
    BUILDERS="$(just _builders {{target}})"; \
    nix build --no-link \
        .#nixosConfigurations.{{target}}.config.system.build.toplevel \
        --builders "$BUILDERS" \
        --builders-use-substitutes --max-jobs 1 --show-trace

builder-preflight target=profile:
    BUILDERS="$(just _builders {{target}})"; \
    sudo ./scripts/builder-preflight.sh "$BUILDERS"

update:
    nix flake update

# Bump all inputs, then dry-build every host; revert the lock if any fails.
# Guards against bleeding-edge nixpkgs/git-tip inputs breaking a build.
update-safe:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! git diff --quiet -- flake.lock || ! git diff --cached --quiet -- flake.lock; then
        echo ":: flake.lock already modified (worktree or index); refusing update" >&2
        exit 1
    fi
    backup=$(mktemp)
    cp -- flake.lock "$backup"
    evidence_backup=''
    evidence_started=false
    evidence_existed=false
    cleanup() {
        status=$?
        if (( status != 0 )); then
            echo ":: update failed — restoring pre-update flake.lock" >&2
            cp -- "$backup" flake.lock || { echo ":: restore failed; backup retained at $backup" >&2; exit 1; }
            if "$evidence_started"; then
                if "$evidence_existed"; then
                    cp -- "$evidence_backup" "$evidence" || { echo ":: receipt restore failed; backup retained at $evidence_backup" >&2; exit 1; }
                elif [[ -f "$evidence" ]]; then
                    rm -f -- "$evidence"
                fi
            fi
        fi
        rm -f -- "$backup"
        if [[ -n "$evidence_backup" ]]; then rm -f -- "$evidence_backup"; fi
        exit "$status"
    }
    trap cleanup EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    baseline=$(git rev-parse HEAD)
    nix flake update
    just dry-all
    evidence=$(git rev-parse --git-path upgrade-candidate.json)
    if [[ -f "$evidence" ]]; then
        evidence_backup=$(mktemp)
        cp -- "$evidence" "$evidence_backup"
        evidence_existed=true
    fi
    evidence_started=true
    python3 scripts/upgrade-candidate-evidence.py "$baseline" "$backup"

# Bump a single input in isolation (e.g. just update-input hyprland), so a
# volatile git-tip input's breakage doesn't get tangled with a nixpkgs bump.
update-input input:
    nix flake update {{ input }}

# Resolve a reviewed Graphify wheel-lock update; never runs during a build.
[positional-arguments]
update-graphify version:
    python3 scripts/update-graphify-lock.py "$1"

upgrade target=profile:
    just _host-guard {{target}} && \
    nix flake update
    BUILDERS="$(just _builders {{target}})" && \
    sudo nixos-rebuild switch --flake .#{{target}} --show-trace \
        --option builders "$BUILDERS" \
        --option builders-use-substitutes true --max-jobs 1

dry target=profile:
    BUILDERS="$(just _builders {{target}})"; \
    sudo nixos-rebuild dry-build --flake .#{{target}} --show-trace \
        --option builders "$BUILDERS" \
        --option builders-use-substitutes true --max-jobs 1

# Build fleet toplevels in one scheduler invocation so independent host graphs
# run concurrently and shared derivations are built once. Does not create links.
build-all:
    #!/usr/bin/env bash
    set -euo pipefail
    configurations=$(nix eval .#nixosConfigurations --apply builtins.attrNames --json)
    hosts=$(nix eval .#fleet.hosts --apply "$(< scripts/upgrade-hosts.nix)" --json)
    names=$(jq -er --argjson configurations "$configurations" 'if type == "array" and length > 0 and all(.[]; type == "string" and test("^[A-Za-z0-9_][A-Za-z0-9_-]*$")) and ($configurations | type == "array") and (. - $configurations | length == 0) then .[] else error("invalid or missing fleet NixOS configurations") end' <<<"$hosts")
    installables=()
    while IFS= read -r host; do
        installables+=(".#nixosConfigurations.$host.config.system.build.toplevel")
    done <<<"$names"
    nix build --no-link "${installables[@]}" \
        --builders '{{orion_builder}} ; {{apollo_builder}}' \
        --builders-use-substitutes --max-jobs 1 --keep-going --show-trace

# Compare evaluated managed-host derivations without building or activating.
[positional-arguments]
upgrade-impact before after:
    #!/usr/bin/env bash
    exec python3 scripts/upgrade-impact.py "$1" "$2"

dry-all:
    just build-all

lint:
    statix check . -c .statix.toml -i '.direnv/*'

fmt:
    nix fmt ./

fmt-check:
    alejandra --check .

# Verify every in-repo markdown link under docs/ (plus the root README/INSTALL)
# resolves to a real file. Fails on any broken link — keeps the docs index honest.
docs-check:
    #!/usr/bin/env bash
    set -euo pipefail
    broken=0
    files=$(find docs -type f -name '*.md'; ls README.md 2>/dev/null || true)
    for f in $files; do
        dir=$(dirname "$f")
        while IFS= read -r link; do
            case "$link" in http://*|https://*|mailto:*|\#*|"") continue;; esac
            target="${link%%#*}"
            [ -z "$target" ] && continue
            if [ ! -e "$dir/$target" ]; then
                echo "BROKEN: $f -> $link"
                broken=$((broken+1))
            fi
        done < <(grep -oE '\]\([^)]+\)' "$f" | sed -E 's/^\]\(//; s/\)$//')
    done
    if [ "$broken" -gt 0 ]; then
        echo ":: docs-check FAILED — $broken broken link(s)"
        exit 1
    fi
    echo ":: docs-check OK — all in-repo doc links resolve"

# Dendritic contract checks (docs/reference/dendritic-contract.md). Hard-fails on
# duplicate registered module names or a _-prefixed file that registers (import-tree
# skips it, so the registration silently never happens). Reports — does NOT fail —
# large files and missing generated-file headers. Report-only by design; not wired
# into `just check` until the large domains are split (repo-structure RFC phases).
structure-check:
    #!/usr/bin/env bash
    set -euo pipefail
    fail=0
    echo ":: registered module name uniqueness"
    dups=$(grep -rhoE 'flake\.modules\.(nixos|home)\.[A-Za-z0-9_-]+' modules/ | sort | uniq -d || true)
    if [ -n "$dups" ]; then
        echo "FAIL: duplicate registered module names:"; echo "$dups" | sed 's/^/  /'; fail=1
    fi
    echo ":: _-prefixed files must not register (import-tree skips them)"
    while IFS= read -r f; do
        if grep -qE 'flake\.modules\.' "$f"; then
            echo "FAIL: $f registers into flake.modules but is _-prefixed"; fail=1
        fi
    done < <(find modules -name '_*.nix')
    echo ":: reusable names under host directories"
    while IFS= read -r f; do
        host=$(basename "$(dirname "$f")")
        while IFS= read -r reg; do
            name=${reg##*.}
            case "$name" in
                "$host"-*) ;;
                *) echo "FAIL: $f registers reusable-looking $name under host $host"; fail=1 ;;
            esac
        done < <(grep -hoE 'flake\.modules\.(nixos|home)\.[A-Za-z0-9_-]+' "$f" || true)
    done < <(find modules/hosts -mindepth 2 -maxdepth 2 -name '*.nix' ! -name '_*')
    echo ":: host-prefixed leaves in profiles"
    for host_dir in modules/hosts/*; do
        host=$(basename "$host_dir")
        if grep -nE "m\.(nixos|home)\.${host}-" modules/profiles/*.nix; then
            echo "FAIL: profile imports host-prefixed leaves for $host"; fail=1
        fi
    done
    echo ":: large files (>400 lines) — candidate domains to split (advisory)"
    find modules -name '*.nix' -exec wc -l {} + \
        | awk '$2!="total" && $1>400 {printf "  WARN: %s (%d lines)\n", $2, $1}'
    echo ":: generated hw files missing a generated-file header (advisory)"
    while IFS= read -r f; do
        head -3 "$f" | grep -qiE 'generated|do not edit' || echo "  WARN: $f has no generated-file header"
    done < <(find modules -name '_hw-generated.nix')
    if [ "$fail" -ne 0 ]; then echo ":: structure-check FAILED"; exit 1; fi
    echo ":: structure-check OK (warnings above are advisory)"

# Run the repository hygiene invariants (recipes, tests, docs, assets, split).
hygiene-check:
    #!/usr/bin/env bash
    set -euo pipefail
    python3 tests/repository-hygiene/test_hygiene.py

check:
    @echo ":: Checking docs..."
    just docs-check
    @echo ":: Testing Kindle release agent..."
    just test-kindle-release-agent
    @echo ":: Checking fleet.json freshness..."
    just fleet-check
    @echo ":: Checking repository hygiene..."
    just hygiene-check
    @echo ":: Linting..."
    just lint
    @echo ":: Checking format..."
    just fmt-check
    @echo ":: Dry building all hosts..."
    just dry-all
    @echo ":: All checks passed"

eval:
    nix flake check

diagnose-gateway-reachability target:
    #!/usr/bin/env bash
    set -euo pipefail
    addr="$(jq -r --arg host "{{target}}" '.hosts[$host].tailscaleIp // empty' fleet.json)"
    [ -n "$addr" ] || addr="$(getent ahostsv4 "{{target}}" | awk 'NR == 1 {print $1}')"
    check() {
      cat <<'REMOTE'
      export PATH=/run/current-system/sw/bin
      gw=192.168.10.1
      echo ":: policy route"
      ip route get "$gw"
      ip rule
      ip route show table 52 2>/dev/null || true
      echo ":: Tailscale routing prefs"
      tailscale version | head -1
      tailscale debug prefs | grep -E '"RouteAll"|"AdvertiseTags"|"AdvertiseRoutes"'
      probe=1.1.1.1
      echo ":: routed TCP/443"
      timeout 2 bash -c "exec 3<>/dev/tcp/$probe/443" && echo "reachable" || echo "unreachable"
    REMOTE
    }
    check | ssh -p 2222 erik@"$addr" 'bash -s'

diagnose-tailscale ip:
    ssh -p 2222 erik@{{ip}} "echo ':: peers'; tailscale status; echo ':: dns'; tailscale dns status"

# Read-only failure detail for a compose unit.
diagnose-stack target stack:
    #!/usr/bin/env bash
    set -euo pipefail
    IP="$(just _host-ip {{target}})"
    ssh -p 2222 erik@"$IP" 'export XDG_RUNTIME_DIR=/run/user/$(id -u); systemctl --user status podman-compose-{{stack}}.service --no-pager -n30 || true; journalctl --user -u podman-compose-{{stack}}.service --no-pager -n50'

# Provision a NEW remote host: convert a fresh box (cloud Ubuntu entrypoint, or a
# NixOS-ISO installer) to NixOS via nixos-anywhere. Prefers remote builders with
# one local fallback job; targets substitute from Orion's cache. Stages the sops
# age key so first-boot secrets decrypt, and lets
# the host's disko config partition the disk. <target> = user@ip[:port] of the
# installer entrypoint (ubuntu@<ip> for a cloud image, nixos@<ip> for the NixOS
# ISO). WARNING: wipes the target disk. After it lands: set the host IP in
# meta.nix → `just fleet-json` → `just deploy-rs <host>` for subsequent switches.
provision host target:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p /tmp/nixos-extra-{{host}}/var/lib/sops-staging/
    cp ~/.config/sops/age/keys.txt /tmp/nixos-extra-{{host}}/var/lib/sops-staging/age-keys.txt
    chmod 600 /tmp/nixos-extra-{{host}}/var/lib/sops-staging/age-keys.txt
    trap 'rm -rf /tmp/nixos-extra-{{host}}' EXIT
    export NIX_CONFIG="builders = $(just _builders {{host}})
    max-jobs = 1
    builders-use-substitutes = true"
    nix run github:nix-community/nixos-anywhere -- \
        --flake .#{{host}} \
        --extra-files /tmp/nixos-extra-{{host}} \
        --show-trace \
        {{target}}

nixos-anywhere target ip luks-pass="" user="nixos":
    #!/usr/bin/env bash
    set -euo pipefail
    export NIX_CONFIG="builders = $(just _builders {{target}})
    max-jobs = 1
    builders-use-substitutes = true"
    LUKS_PASS="{{luks-pass}}"
    if [ -z "$LUKS_PASS" ]; then
        read -rsp "Enter LUKS password: " LUKS_PASS
        echo
    fi
    mkdir -p /tmp/nixos-extra/var/lib/sops-staging/
    cp ~/.config/sops/age/keys.txt /tmp/nixos-extra/var/lib/sops-staging/age-keys.txt
    chmod 600 /tmp/nixos-extra/var/lib/sops-staging/age-keys.txt
    LUKS_FILE=$(mktemp)
    printf '%s' "$LUKS_PASS" > "$LUKS_FILE"
    trap 'rm -f "$LUKS_FILE"; rm -rf /tmp/nixos-extra' EXIT
    nix run github:nix-community/nixos-anywhere -- \
        --flake .#{{target}} \
        --extra-files /tmp/nixos-extra \
        --disk-encryption-keys /tmp/luks-password.txt "$LUKS_FILE" \
        --show-trace \
        --generate-hardware-config nixos-generate-config \
            ./modules/hosts/{{target}}/_hw-generated.nix \
        {{user}}@{{ip}}

gc days="5":
    nix-collect-garbage --delete-older-than {{days}}d

store-repair:
    sudo nix-store --verify --check-contents --repair

cache-keygen:
    #!/usr/bin/env bash
    set -euo pipefail
    echo ":: Generating nix-serve cache signing key pair"
    sudo nix-store --generate-binary-cache-key discovery /etc/nix/cache-priv-key.pem /tmp/cache-pub-key.pem
    sudo chmod 600 /etc/nix/cache-priv-key.pem
    echo ":: Private key: /etc/nix/cache-priv-key.pem"
    echo ":: Public key:"
    cat /tmp/cache-pub-key.pem
    echo
    echo ":: Add this public key to nix.settings.trusted-public-keys in Story 3.3"
