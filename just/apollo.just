deploy-ubuntu-work-profile:
    ./scripts/deploy-ubuntu-work-profile.sh

sync-ubuntu-work-brave-settings:
    ./scripts/sync-ubuntu-work-brave-settings.sh

ubuntu-work-warp-connect:
    ssh -o BatchMode=yes -o ConnectTimeout=10 erik@192.168.122.74 'warp-cli --accept-tos connect'

ubuntu-work-define:
    virsh --connect qemu:///system define modules/hosts/endeavour/ubuntu-work-domain.xml

ubuntu-work-view:
    virt-viewer --connect qemu:///system --reconnect --auto-resize=always --attach ubuntu-work

# Read-only verification of Apollo's root pool and data array.
apollo-disk-inventory:
    #!/usr/bin/env bash
    set -euo pipefail
    ssh -p 2222 -o BatchMode=yes -o ConnectTimeout=8 erik@{{ip_apollo}} 'bash -s' <<'REMOTE'
    set -euo pipefail
    lsblk -e7 -o NAME,SIZE,TYPE,FSTYPE,UUID,MOUNTPOINTS,MODEL,SERIAL
    for path in / /mnt/data; do
      findmnt -T "$path" -nro TARGET,SOURCE,FSTYPE,UUID
    done
    cat /proc/mdstat
    sudo -n mdadm --detail /dev/md/microvms
    REMOTE

# Read-only daily proof for Apollo's host, work sessions, and cache.
diagnose-apollo-worklab:
    #!/usr/bin/env bash
    set -euo pipefail
    ssh -p 2222 -o BatchMode=yes -o ConnectTimeout=8 erik@{{ip_apollo}} 'bash -s' <<'REMOTE'
    set -euo pipefail
    echo ':: capacity'
    free -h
    df -h /
    echo ':: failed units'
    failed=$(sudo -n systemctl --failed --no-legend --plain)
    printf '%s\n' "${failed:-none}"
    test -z "$failed"
    echo ':: critical units'
    sudo -n systemctl is-active alloy.service syncthing.service
    echo ':: work sessions'
    systemctl --user is-active \
      herdr-session-homelab.service herdr-session-dataplatform.service
    echo ':: Orion cache'
    curl --fail --silent --show-error --connect-timeout 3 --max-time 5 \
      http://orion:5000/nix-cache-info >/dev/null
    echo 'reachable'
    REMOTE

# Prove project-owned toolchains from the Apollo checkout before host cleanup.
verify-apollo-project-environments:
    #!/usr/bin/env bash
    set -euo pipefail
    ssh -p 2222 -o BatchMode=yes -o ConnectTimeout=8 erik@{{ip_apollo}} 'bash -s' <<'REMOTE'
    set -euo pipefail
    repos=(
      "$HOME/Documents/nstech/dataplatform-spark"
      "$HOME/Documents/nstech/dataplatform-airflow"
      "$HOME/Documents/nstech/dataplatform-datacontracts"
    )
    for repo in "${repos[@]}"; do
      printf ':: devenv test %s\n' "${repo##*/}"
      test -d "$repo/.git"
      (cd "$repo" && devenv test)
    done
    REMOTE

# Clone the explicit work-lab allowlist from local Git bundles, without credentials.
bootstrap-apollo-worklab-repositories:
    #!/usr/bin/env bash
    set -euo pipefail
    bundle_dir=$(mktemp -d)
    trap 'rm -rf -- "$bundle_dir"' EXIT
    root=$PWD
    specs=(
      "homelab|$root/../homelab|Documents/erik/homelab"
      "dataplatform|$root/../../nstech/dataplatform|Documents/nstech/dataplatform"
      "dataplatform-spark|$root/../../nstech/dataplatform-spark|Documents/nstech/dataplatform-spark"
      "dataplatform-airflow|$root/../../nstech/dataplatform-airflow|Documents/nstech/dataplatform-airflow"
      "dataplatform-datacontracts|$root/../../nstech/dataplatform-datacontracts|Documents/nstech/dataplatform-datacontracts"
    )
    for spec in "${specs[@]}"; do
      IFS='|' read -r name local_repo remote_path <<<"$spec"
      test -d "$local_repo/.git"
      origin=$(git -C "$local_repo" config --get remote.origin.url)
      case "$origin" in git@*:*) ;; *) echo "unsupported origin for $name" >&2; exit 2;; esac
      bundle="$bundle_dir/$name.bundle"
      git -C "$local_repo" bundle create "$bundle" --all
      scp -P 2222 -q "$bundle" "erik@{{ip_apollo}}:/tmp/apollo-$name.bundle"
      ssh -p 2222 -o BatchMode=yes -o ConnectTimeout=8 erik@{{ip_apollo}} \
        'bash -s' -- "$name" "$remote_path" "$origin" <<'REMOTE'
    set -euo pipefail
    name=$1
    remote_path=$2
    origin=$3
    bundle="/tmp/apollo-$name.bundle"
    target="$HOME/$remote_path"
    trap 'rm -f "$bundle"' EXIT
    git bundle list-heads "$bundle" >/dev/null
    mkdir -p "$(dirname "$target")"
    if [ -e "$target" ]; then
      test -d "$target/.git"
    else
      git clone "$bundle" "$target"
    fi
    git -C "$target" remote set-url origin "$origin"
    REMOTE
    done
    local_cli="$root/../../nstech/dataplatform-datacontracts/.devenv/state/contract-cli"
    remote_cli=Documents/nstech/dataplatform-datacontracts/.devenv/state/contract-cli
    test -x "$local_cli/contract-cli"
    test -s "$local_cli/.version"
    ssh -p 2222 -o BatchMode=yes erik@{{ip_apollo}} 'bash -s' -- "$remote_cli" <<'REMOTE'
    set -euo pipefail
    remote_cli=$1
    mkdir -p "$HOME/$remote_cli"
    REMOTE
    scp -P 2222 -q "$local_cli/contract-cli" "$local_cli/.version" \
      "erik@{{ip_apollo}}:$remote_cli/"
    ssh -p 2222 -o BatchMode=yes erik@{{ip_apollo}} 'bash -s' -- "$remote_cli" <<'REMOTE'
    set -euo pipefail
    remote_cli=$1
    chmod 0755 "$HOME/$remote_cli/contract-cli"
    chmod 0644 "$HOME/$remote_cli/.version"
    REMOTE
    remote_devenv=Documents/nstech/dataplatform-datacontracts/devenv.nix
    if ! ssh -p 2222 -o BatchMode=yes erik@{{ip_apollo}} \
      'git -C "$HOME/Documents/nstech/dataplatform-datacontracts" diff --quiet -- devenv.nix'; then
      cmp -s "$root/../../nstech/dataplatform-datacontracts/devenv.nix" \
        <(ssh -p 2222 -o BatchMode=yes erik@{{ip_apollo}} "cat '$remote_devenv'") || {
        echo "refusing to overwrite changed $remote_devenv" >&2
        exit 2
      }
    fi
    scp -P 2222 -q "$root/../../nstech/dataplatform-datacontracts/devenv.nix" \
      "erik@{{ip_apollo}}:$remote_devenv"
    scp -P 2222 -q "$root/../../nstech/dataplatform-airflow/devenv.nix" \
      "erik@{{ip_apollo}}:Documents/nstech/dataplatform-airflow/devenv.nix"
    scp -P 2222 -q "$root/../../nstech/dataplatform-airflow/devenv.lock" \
      "erik@{{ip_apollo}}:Documents/nstech/dataplatform-airflow/devenv.lock"
    ssh -p 2222 -o BatchMode=yes erik@{{ip_apollo}} \
      'cd "$HOME/Documents/nstech/dataplatform-airflow" && cp -n .env.example .env'
