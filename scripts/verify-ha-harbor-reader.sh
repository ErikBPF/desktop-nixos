#!/usr/bin/env bash
set -euo pipefail

if [[ $# != 1 || ! $1 =~ ^harbor\.homelab\.pastelariadev\.com/ha-harness/ha-harness@sha256:[0-9a-f]{64}$ ]]; then
    echo 'Expected the fixed HA Harbor repository pinned by lowercase sha256 digest' >&2
    exit 2
fi
image=$1
if ! ip=$(just --no-dotenv --quiet _host-ip discovery 2>/dev/null); then
    echo 'Could not resolve Discovery from owner fleet.json' >&2
    exit 1
fi

# Only the validated, nonsecret image reference enters the remote command.
if ! timeout --signal=KILL 315 ssh -T -p 2222 -o BatchMode=yes \
    -o StrictHostKeyChecking=yes -o ForwardAgent=no -o ConnectTimeout=8 \
    -o ServerAliveInterval=15 -o ServerAliveCountMax=2 "erik@$ip" \
    "sudo -n env -i HOME=/root PATH=/run/current-system/sw/bin /run/current-system/sw/bin/timeout --signal=KILL 300 /run/current-system/sw/bin/bash -s -- '$image'" \
    >/dev/null 2>&1 <<'REMOTE'
set -euo pipefail
docker_reader() {
    /run/current-system/sw/bin/docker --config /run/harbor-reader --host unix:///run/docker.sock "$@"
}
docker_reader image pull "$1" >/dev/null
docker_reader image inspect --format '{{range .RepoDigests}}{{println .}}{{end}}' "$1" | grep -Fx -- "$1" >/dev/null
REMOTE
then
    echo 'Discovery managed-reader pull verification failed (details suppressed)' >&2
    exit 1
fi
printf 'imageDigest=%s\npulled using configured managed-reader auth path\n' "$image"
