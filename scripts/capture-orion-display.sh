#!/usr/bin/env bash
# Read-only snapshot, streamed over SSH by `just capture-orion-display`.
set -uo pipefail
XDG_RUNTIME_DIR="/run/user/$(id -u)"
export XDG_RUNTIME_DIR

# A wedged compositor must not prevent the remaining evidence being collected.
capture() {
    printf '\n### %s\n' "$*"
    timeout -k 2s 10s "$@" 2>&1 || printf 'CAPTURE_FAILED status=%s\n' "$?"
}

capture date --iso-8601=seconds
capture uname -a
capture nixos-version
capture readlink -f /run/current-system /run/booted-system /run/opengl-driver
capture cat /proc/cmdline /proc/sys/kernel/random/boot_id
capture loginctl list-sessions --no-legend
capture loginctl seat-status seat0
capture ps -C gamescope,steam,Hyprland,hypridle,hyprlock,Xwayland -o pid,lstart,comm
capture gamescope --version
capture hyprctl instances -j
if timeout -k 2s 10s pgrep -x Hyprland >/dev/null; then
    capture hyprctl -i 0 version
    capture hyprctl -i 0 monitors all -j
fi
capture systemctl --user list-units --all 'gamescope*' 'steam*' '*hypr*'
capture systemctl --user show gamescope-session.service steam-launcher.service -p Id -p MainPID -p ExecMainStartTimestamp -p NRestarts -p StandardOutput -p StandardError
capture systemctl show sleep.target suspend.target hibernate.target -p Id -p LoadState -p ActiveState

shopt -s nullglob
for connector in /sys/class/drm/card*-*; do
    [[ -f "$connector/status" ]] || continue
    capture cat "$connector/status" "$connector/enabled" "$connector/modes"
    # Preserve the real EDID as base64 even when the connector later disappears.
    capture base64 -w 0 "$connector/edid"
    printf '\n'
done
for device in /sys/class/drm/card[0-9]*/device; do
    [[ -f "$device/vendor" ]] || continue
    capture cat "$device/vendor" "$device/device" "$device/power_dpm_force_performance_level"
done

# Keep the full kernel context; restrict userspace logs to graphics processes.
# No environment dump, Steam account files, or unrelated service journals.
capture sudo -n journalctl -k -b --since '30 minutes ago' -o short-precise --no-pager
capture journalctl --user -b --since '30 minutes ago' -o short-precise --no-pager \
    _COMM=gamescope _COMM=steam _COMM=Hyprland _COMM=hypridle _COMM=hyprlock _COMM=Xwayland
capture journalctl --user -b --since '30 minutes ago' -o short-precise --no-pager \
    -u gamescope-session -u steam-launcher -u steamos-manager -u hypridle
capture sudo -n journalctl -b --since '30 minutes ago' -o short-precise --no-pager \
    -u systemd-logind -u systemd-suspend -u greetd
capture date --iso-8601=seconds
printf '\nSnapshot finished; inspect CAPTURE_FAILED markers for missing evidence.\n'
