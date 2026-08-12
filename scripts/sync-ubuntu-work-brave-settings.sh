#!/usr/bin/env bash
set -euo pipefail

source_profile="$HOME/.config/BraveSoftware/Brave-Browser/Default"
target="${UBUNTU_WORK_SSH_TARGET:-erik@192.168.122.74}"
ssh_options=(-o BatchMode=yes -o ConnectTimeout=10)
scratch="$(mktemp -d)"
trap 'rm -rf -- "$scratch"' EXIT

test -s "$source_profile/Preferences"
test -s "$source_profile/Bookmarks"
test -s "$source_profile/History"
test -d "$source_profile/Extensions"

extension_ids="$scratch/extension-ids"
find "$source_profile/Extensions" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort \
  | while read -r id; do
      curl --fail --location --silent --output /dev/null --max-time 15 \
        "https://clients2.google.com/service/update2/crx?response=redirect&prodversion=151.0.0.0&acceptformat=crx3&x=id%3D$id%26uc" \
        && printf '%s\n' "$id"
    done >"$extension_ids"
jq -Rsc '
  split("\n") | map(select(length == 32))
  | {ExtensionInstallForcelist: map(. + ";https://clients2.google.com/service/update2/crx")}
' "$extension_ids" >"$scratch/extensions-policy.json"
jq -e '.ExtensionInstallForcelist | length > 0' "$scratch/extensions-policy.json" >/dev/null

jq '{
  bookmark_bar,
  browser: {theme: ((.browser.theme // {}) + {color_scheme2: 2})},
  brave: {
    accelerators: .brave.accelerators,
    always_show_bookmark_bar_on_ntp: .brave.always_show_bookmark_bar_on_ntp,
    enable_window_closing_confirm: .brave.enable_window_closing_confirm,
    sidebar: .brave.sidebar
  },
  intl,
  spellcheck,
  toolbar
}' "$source_profile/Preferences" >"$scratch/portable-settings.json"
install -m 0600 "$source_profile/Bookmarks" "$scratch/Bookmarks"
cp --reflink=auto "$source_profile/History" "$scratch/History"
if test -s "$source_profile/History-journal"; then
  cp --reflink=auto "$source_profile/History-journal" "$scratch/History-journal"
fi
sqlite3 "$scratch/History" 'PRAGMA journal_mode=DELETE; PRAGMA quick_check;' | grep -qx ok

ssh "${ssh_options[@]}" "$target" '
  set -e
  pkill -TERM -x brave 2>/dev/null || true
  for _ in $(seq 1 20); do
    pgrep -x brave >/dev/null || break
    sleep 0.25
  done
  ! pgrep -x brave >/dev/null
  install -d -m 0700 "$HOME/.config/ubuntu-work-profile/brave-migration"
'

rsync --archive --chmod=F600 -e "ssh -o BatchMode=yes -o ConnectTimeout=10" \
  "$scratch/" "$target:.config/ubuntu-work-profile/brave-migration/"

ssh "${ssh_options[@]}" "$target" '
  set -e
  incoming="$HOME/.config/ubuntu-work-profile/brave-migration"
  backup="$HOME/.local/state/ubuntu-work/brave-backup/$(date +%Y%m%d-%H%M%S)"
  install -d -m 0700 "$backup"
  sudo test ! -e /etc/brave/policies/managed/90-user-extensions.json ||
    sudo cp -a /etc/brave/policies/managed/90-user-extensions.json "$backup/"
  test "$("$HOME/.nix-profile/bin/sqlite3" "$incoming/History" "PRAGMA quick_check")" = ok
  for browser_dir in Brave-Browser Brave-Browser-Xpra; do
    profile="$HOME/.config/BraveSoftware/$browser_dir/Default"
    install -d -m 0700 "$profile" "$backup/$browser_dir"
    cp -a "$profile/Preferences" "$profile/Bookmarks" "$profile/History" "$backup/$browser_dir/" 2>/dev/null || true
    if test -s "$profile/Preferences"; then
      jq -s ".[0] * .[1]" "$profile/Preferences" "$incoming/portable-settings.json" >"$incoming/Preferences.new"
    else
      cp "$incoming/portable-settings.json" "$incoming/Preferences.new"
    fi
    jq empty "$incoming/Preferences.new" >/dev/null
    install -m 0600 "$incoming/Preferences.new" "$profile/Preferences"
    install -m 0600 "$incoming/Bookmarks" "$profile/Bookmarks"
    find "$profile" -maxdepth 1 -name History-journal -delete
    install -m 0600 "$incoming/History" "$profile/History"
  done
  sudo install -d -m 0755 /etc/brave/policies/managed
  sudo install -m 0644 "$incoming/extensions-policy.json" /etc/brave/policies/managed/90-user-extensions.json
  gsettings set org.gnome.desktop.interface color-scheme prefer-dark
  gsettings set org.gnome.desktop.interface gtk-theme Yaru-dark
  XDG_RUNTIME_DIR=/run/user/1000 \
  DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus \
  systemd-run --user --collect --unit=work-browser-retest \
    --setenv=DISPLAY=:0 \
    --setenv=WAYLAND_DISPLAY=wayland-0 \
    --setenv=XDG_RUNTIME_DIR=/run/user/1000 \
    --setenv=DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus \
    "$HOME/.nix-profile/bin/work-browser" --restore-last-session
'
