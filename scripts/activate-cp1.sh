#!/usr/bin/env bash
# Run on Kepler through the owner recipe, after exact artifacts are staged.
set -euo pipefail
manifest=${1:?reviewed manifest required}
mode=${2:-preview}
case "$mode" in preview|activate) ;; *) echo 'expected preview or activate' >&2; exit 2;; esac
[[ $(hostname) == kepler ]] || { echo 'not Kepler' >&2; exit 1; }
jq -e '
  (.sourceRevision | test("^[a-f0-9]{40}$")) and
  (.baseline.hardware == .candidate.hardware) and
  (.candidate.clusterInit == false) and
  (.candidate.serverAddr == "https://10.250.0.13:6443") and
  (.candidate.restart == "no") and
  (.candidate.timeoutStartSec == 300) and
  (.candidate.bootstrapTimer == false and .candidate.bootstrapService == false) and
  (.baseline.guestBootId | test("^[a-f0-9-]{36}$")) and
  (.knownHostsSha256 | test("^[a-f0-9]{64}$")) and
  ([.baseline.bootstrapTimerState,.baseline.bootstrapServiceState] |
    all(.[]; . == "enabled" or . == "disabled" or . == "static" or . == "masked" or . == "masked-runtime")) and
  ([.baseline.hostCurrent,.baseline.hostProfile,.baseline.guestCurrent,.baseline.guestProfile,
    .baseline.runner,.candidate.toplevel,.candidate.runner,.candidate.nix,.candidate.registration,.candidate.conditionSystemd,
    .candidate.hardware.kernel,.candidate.hardware.initrd] |
    all(.[]; type == "string" and test("^/nix/store/[a-z0-9]{32}-[A-Za-z0-9+._/-]+$") and (split("/") | all(.[]; . != ".." and . != "."))))
' "$manifest" >/dev/null
get() { jq -er "$1" "$manifest"; }
old=$(get .baseline.guestCurrent)
new=$(get .candidate.toplevel)
[[ "$old" != "$new" ]] || { echo 'candidate equals baseline' >&2; exit 1; }
check_host() {
  [[ $(readlink -e /run/current-system) == "$(get .baseline.hostCurrent)" ]]
  [[ $(readlink -e /nix/var/nix/profiles/system) == "$(get .baseline.hostProfile)" ]]
  [[ $(readlink -e /var/lib/microvms/cp-1/current) == "$(get .baseline.runner)" ]]
}
check_host
known=$(get .knownHosts)
[[ -f "$known" && ! -L "$known" ]]
[[ $(sha256sum "$known" | cut -d' ' -f1) == "$(get .knownHostsSha256)" ]]
for system in "$old" "$new"; do
  [[ $(readlink -e "$system/kernel") == "$(get .candidate.hardware.kernel)" ]]
  [[ $(readlink -e "$system/initrd") == "$(get .candidate.hardware.initrd)" ]]
done
[[ -x "$new/bin/switch-to-configuration" ]]
[[ $(readlink -e "$(get .candidate.runner)/share/microvm/system") == "$new" ]]
# Source-disabled bootstrap units must be effective masks, not assumed /run overrides.
for unit in k3s-bootstrap-secrets.timer k3s-bootstrap-secrets.service; do
  [[ $(readlink -f "$new/etc/systemd/system/$unit") == /dev/null ]]
done
python3 - "$old" "$new" "$(get .candidate.timeoutStartSec)" "$(get .candidate.conditionSystemd)" <<'PY'
from pathlib import Path
import re, sys
old, new = (Path(p) / 'etc/systemd/system' for p in sys.argv[1:3])
allowed = {'k3s.service', 'k3s-bootstrap-secrets.service', 'k3s-bootstrap-secrets.timer', 'k3s-manifest-reconcile.service'}
for name in sorted({str(p.relative_to(root)) for root in (old,new) for p in root.rglob('*') if not p.is_dir()}):
    if Path(name).name in allowed: continue
    a,b = old/name,new/name
    if not a.exists() or not b.exists() or a.read_bytes() != b.read_bytes():
        raise SystemExit('unrelated guest unit change: '+name)
a,b = ((root/'k3s.service').read_text() for root in (old,new))
assert '\nRestart=no\n' in b and any('\nTimeoutStartSec='+value+'\n' in b for value in ('300','300s','5min'))
assert '--cluster-init' not in b and re.search(r'--server(?:=|\s+)https://10\.250\.0\.13:6443(?:\s|$)',b)
def stable(text):
    return '\n'.join(line for line in text.splitlines() if not re.match(r'^(Restart=|TimeoutStartSec=|\s*--cluster-init(?:\s|$)|\s*--server(?:=|\s))',line))
assert stable(a) == stable(b), 'unexpected K3s unit change'
a,b = ((root/'k3s-manifest-reconcile.service').read_text() for root in (old,new))
condition = 'ExecCondition='+sys.argv[4]+'/bin/systemctl is-active --quiet k3s.service'
assert b.count(condition+'\n') == 1
assert 'Wants=k3s.service\n' in a and 'Wants=k3s.service\n' not in b
assert a.replace('Wants=k3s.service\n','') == b.replace(condition+'\n',''), 'unexpected manifest reconciler change'

PY
ssh_options=(-F /dev/null -o BatchMode=yes -o ConnectTimeout=8 -o ConnectionAttempts=1
  -o StrictHostKeyChecking=yes -o "UserKnownHostsFile=$known" -o GlobalKnownHostsFile=/dev/null)
# Store paths and boot ID above have a strict alphabet before SSH's remote shell.
set +e
timeout 540 ssh "${ssh_options[@]}" root@10.250.0.11 bash -se -- \
  "$mode" "$old" "$new" "$(get .baseline.guestProfile)" "$(get .baseline.guestBootId)" \
  "$(get .candidate.nix)" "$(get .candidate.registration)" \
  "$(get .baseline.bootstrapTimerState)" "$(get .baseline.bootstrapServiceState)" <<'GUEST'
set -euo pipefail
mode=$1; old=$2; new=$3; profile=$4; boot=$5; nix=$6; registration=$7
timer_state=$8; bootstrap_state=$9
[[ $(hostname) == cp-1 ]]
[[ $(cat /proc/sys/kernel/random/boot_id) == "$boot" ]]
[[ $(readlink -e /run/current-system) == "$old" ]]
[[ $(readlink -e /nix/var/nix/profiles/system) == "$profile" ]]
[[ $(timeout 10 systemctl is-enabled k3s-bootstrap-secrets.timer || true) == "$timer_state" ]]
[[ $(timeout 10 systemctl is-enabled k3s-bootstrap-secrets.service || true) == "$bootstrap_state" ]]
for unit in k3s.service k3s-bootstrap-secrets.timer k3s-bootstrap-secrets.service k3s-manifest-reconcile.service; do
  state=$(systemctl is-active "$unit" || true)
  [[ "$state" == inactive || "$state" == failed ]]
  [[ $(timeout 10 systemctl show "$unit" --property=MainPID --value) == 0 ]]
done
timeout 60 "$new/bin/switch-to-configuration" dry-activate
[[ "$mode" == activate ]] || exit 0
fail_stop() {
  status=$?
  trap - EXIT
  if (( status != 0 )); then
    timeout 30 systemctl stop k3s.service k3s-bootstrap-secrets.timer k3s-bootstrap-secrets.service k3s-manifest-reconcile.service || true
    if [[ $(timeout 10 systemctl show k3s.service --property=MainPID --value) == 0 ]]; then
      echo 'activation failed; K3s PID is zero; no old configuration restarted' >&2
    else
      echo 'activation failed; K3s containment UNVERIFIED; stop operator work' >&2
    fi
  fi
  exit "$status"
}
trap fail_stop EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
"$nix/bin/nix-store" --load-db < "$registration"
"$nix/bin/nix-env" -p /nix/var/nix/profiles/system --set "$new"
timeout 360 "$new/bin/switch-to-configuration" switch
[[ $(cat /proc/sys/kernel/random/boot_id) == "$boot" ]]
[[ $(readlink -e /run/current-system) == "$new" ]]
[[ $(timeout 10 systemctl is-active k3s.service || true) == active ]]
[[ $(timeout 10 systemctl show k3s.service --property=Restart --value) == no ]]
for unit in k3s-bootstrap-secrets.timer k3s-bootstrap-secrets.service; do
  [[ $(systemctl show "$unit" --property=LoadState --value) == masked ]]
  [[ $(systemctl is-active "$unit" || true) != active ]]
done
GUEST
status=$?
set -e
check_host || { echo 'host or runner changed; stop and investigate' >&2; exit 1; }
(( status == 0 )) || exit "$status"
printf '%s completed; runner unchanged; no etcd recovery claim\n' "$mode"
