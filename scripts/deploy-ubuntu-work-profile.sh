#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source_dir="$repo_root/profiles/ubuntu-work"
target="${UBUNTU_WORK_SSH_TARGET:-erik@192.168.122.74}"
ssh_options=(-o BatchMode=yes -o ConnectTimeout=10)

ssh "${ssh_options[@]}" "$target" '
  set -e
  if ! command -v nix >/dev/null || ! dpkg-query -W qemu-guest-agent >/dev/null 2>&1; then
    sudo apt-get update
    sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y nix-bin nix-setup-systemd qemu-guest-agent
  fi
  sudo usermod -aG nix-users "$USER"
  sudo systemctl enable --now nix-daemon.service
  sudo ln -sfn /usr/share/doc/nix-bin/examples/nix-profile-daemon.sh /etc/profile.d/nix.sh
  install -d -m 0700 "$HOME/.config/ubuntu-work-profile"
'

rsync --archive --delete -e "ssh -o BatchMode=yes -o ConnectTimeout=10" \
  "$source_dir/" "$target:.config/ubuntu-work-profile/"
rsync --archive -e "ssh -o BatchMode=yes -o ConnectTimeout=10" \
  "$repo_root/config/keyboard/us_qwerty-fr" "$target:.config/ubuntu-work-profile/qwerty-fr"

ssh "${ssh_options[@]}" "$target" '
  set -e
  install -d -m 0700 "$HOME/.config/nix"
  install -m 0600 "$HOME/.config/ubuntu-work-profile/nix.conf" "$HOME/.config/nix/nix.conf"
  cd "$HOME/.config/ubuntu-work-profile"
  nix build --profile "$HOME/.nix-profile" .#default
  install -d -m 0700 "$HOME/.config/autostart"
  rm -f "$HOME/.config/autostart/brave-browser.desktop"
  sudo install -m 0644 "$HOME/.config/ubuntu-work-profile/qwerty-fr" /usr/share/X11/xkb/symbols/qwerty-fr
  sudo install -m 0644 "$HOME/.nix-profile/share/ubuntu-work/sshd_config" /etc/ssh/sshd_config.d/90-nix-work.conf
  sudo /usr/sbin/sshd -t
  sudo systemctl reload ssh
  "$HOME/.nix-profile/bin/work-browser" --version
  "$HOME/.nix-profile/bin/ssh" -V
  "$HOME/.nix-profile/bin/tmux" -V
  for package in cloudflare-warp ampagent ds-agent; do
    dpkg-query -W "$package" >/dev/null
  done
  for service in warp-svc.service konea.service ds_agent.service tmxbc.service; do
    systemctl is-active --quiet "$service"
  done
'
