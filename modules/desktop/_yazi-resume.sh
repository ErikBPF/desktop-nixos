# shellcheck shell=bash
set -euo pipefail

state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/yazi"
state_file="$state_dir/last-cwd"
mkdir -p "$state_dir"

start_dir="$HOME"
if [[ -r "$state_file" ]]; then
  IFS= read -r saved_dir <"$state_file" || true
  if [[ -d "${saved_dir:-}" ]]; then
    start_dir="$saved_dir"
  fi
fi

cwd_file="$(mktemp "$state_dir/.cwd.XXXXXX")"
state_tmp="$(mktemp "$state_dir/.last-cwd.XXXXXX")"
trap 'rm -f "$cwd_file" "$state_tmp"' EXIT

yazi "$start_dir" --cwd-file "$cwd_file"

if IFS= read -r cwd <"$cwd_file" && [[ -d "$cwd" ]]; then
  printf '%s\n' "$cwd" >"$state_tmp"
  mv "$state_tmp" "$state_file"
fi
