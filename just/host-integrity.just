# Source-owned entry points for the bounded Endeavour pilot; no deployment wrapper.
_integrity-window:
    #!/usr/bin/env bash
    set -euo pipefail
    just _host-guard endeavour
    for unit in restic-backups-endeavour-home host-integrity-signatures host-integrity-store host-integrity-av; do
        state=$(systemctl show "$unit.service" --property=ActiveState --value)
        case "$state" in active|activating|deactivating) echo "BLOCKED: $unit is $state" >&2; exit 2;; esac
    done
    if [ -n "$(systemctl list-units 'host-integrity-av-canary@*.service' --state=active,activating,deactivating --no-legend --plain)" ]; then
        echo 'BLOCKED: another canary is active' >&2; exit 2
    fi
    available=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)
    [ "$available" -ge 4194304 ] || { echo 'BLOCKED: less than 4 GiB available RAM' >&2; exit 2; }
    scratch=$(df -B1 --output=avail /run | tail -1)
    [ "$scratch" -ge 1073741824 ] || { echo 'BLOCKED: less than 1 GiB free in /run' >&2; exit 2; }
    awk '/^(MemAvailable|SwapTotal|SwapFree):/ {print}' /proc/meminfo
    for check in signatures store av; do
        if systemctl is-active --quiet "host-integrity-$check.timer"; then
            echo 'BLOCKED: pause integrity timers before controlled work' >&2; exit 2
        fi
    done

integrity-status:
    #!/usr/bin/env bash
    set -euo pipefail
    just _host-guard endeavour
    systemctl show alloy.service host-integrity-report.service host-integrity-signatures.service host-integrity-store.service host-integrity-av.service --property=Id,LoadState,ActiveState,Result,ExecMainStatus,MemoryPeak,CPUUsageNSec,IOReadBytes,IOWriteBytes
    systemctl list-timers 'host-integrity-*' --all --no-pager
    for check in signatures store av; do
        printf '%s\n' "$check"
        sudo host-integrity-pilot status --config "/etc/host-integrity/$check.json"
    done

integrity-pause:
    just _host-guard endeavour
    sudo systemctl stop host-integrity-signatures.timer host-integrity-store.timer host-integrity-av.timer

integrity-store-preflight: _integrity-window
    sudo systemctl start host-integrity-store-preflight.service
    systemctl show host-integrity-store-preflight.service --property=Result,ExecMainStatus

[positional-arguments]
integrity-start check: _integrity-window
    #!/usr/bin/env bash
    set -euo pipefail
    case "$1" in signatures|store|av) ;; *) echo 'Unknown integrity check' >&2; exit 2;; esac
    sudo systemctl start "host-integrity-$1.service"
    sudo host-integrity-pilot status --config "/etc/host-integrity/$1.json"

[positional-arguments]
integrity-canary case: _integrity-window
    #!/usr/bin/env bash
    set -euo pipefail
    case "$1" in finding|partial|error) ;; *) echo 'Unknown canary case' >&2; exit 2;; esac
    sudo systemctl start "host-integrity-av-canary@$1.service"
    sudo host-integrity-pilot status --config /etc/host-integrity/av.json

[positional-arguments]
integrity-resolve expected_digest review_file: _integrity-window
    #!/usr/bin/env bash
    set -euo pipefail
    sudo host-integrity-pilot resolve --config /etc/host-integrity/av.json --expected-state-sha256 "$1" --review-file "$2"
    sudo host-integrity-pilot status --config /etc/host-integrity/av.json

# Restore only the explicitly recorded, still-present known-good Endeavour generation.
[positional-arguments]
integrity-rollback generation closure:
    #!/usr/bin/env bash
    set -euo pipefail
    just _host-guard endeavour
    [[ "$1" =~ ^[0-9]+$ ]] || { echo 'Invalid baseline generation' >&2; exit 2; }
    case "$2" in /nix/store/*-nixos-system-endeavour-*) ;; *) echo 'Invalid Endeavour closure' >&2; exit 2;; esac
    test "$(readlink -f "/nix/var/nix/profiles/system-$1-link")" = "$2"
    test -x "$2/bin/switch-to-configuration"
    sudo nix-env --profile /nix/var/nix/profiles/system --switch-generation "$1"
    sudo "$2/bin/switch-to-configuration" switch
    test "$(readlink -f /run/current-system)" = "$2"
    test "$(readlink -f /nix/var/nix/profiles/system)" = "$2"
