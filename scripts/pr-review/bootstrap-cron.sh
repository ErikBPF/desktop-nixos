#!/usr/bin/env bash
# Install the ready probe and create the Hermes cron job once. Idempotent.
set -euo pipefail

: "${HERMES_CONTAINER:=hermes-daedalus}"
: "${HERMES_CLI:=/opt/hermes/.venv/bin/hermes}"
: "${DATA_DIR:?DATA_DIR is required}"
: "${READY_SCRIPT:?READY_SCRIPT is required}"
: "${AGENT_UID:=10000}"
: "${AGENT_GID:=10000}"
: "${JOB_NAME:=hermes-pr-review}"
: "${SCHEDULE:=*/10 * * * *}"

install -d -o "$AGENT_UID" -g "$AGENT_GID" -m 0755 "$DATA_DIR/scripts"
install -m 0755 -o "$AGENT_UID" -g "$AGENT_GID" "$READY_SCRIPT" \
  "$DATA_DIR/scripts/pr-review-ready.py"

for _ in $(seq 1 60); do
  if docker inspect -f '{{.State.Running}}' "$HERMES_CONTAINER" 2>/dev/null | grep -qx true; then
    break
  fi
  sleep 2
done

list_file="$(mktemp)"
trap 'rm -f "$list_file"' EXIT

for _ in $(seq 1 60); do
  if docker exec -u "$AGENT_UID:$AGENT_GID" -e HOME=/opt/data "$HERMES_CONTAINER" "$HERMES_CLI" cron list --all \
    >"$list_file" 2>/dev/null; then
    break
  fi
  sleep 2
done

if ! docker exec -u "$AGENT_UID:$AGENT_GID" "$HERMES_CONTAINER" \
  test -r /opt/skills-development/cr-pr/SKILL.md; then
  echo "cr-pr skill is not mounted; run: just sync-hermes-skills discovery" >&2
  exit 1
fi

if grep -Fq "$JOB_NAME" "$list_file"; then
  exit 0
fi

prompt='Review every bundle marked READY by the script output. For each bundle:
1. Read /opt/data/review-in/<id>/request.md and meta.json.
2. Load the base-pinned skills in /opt/data/review-in/<id>/skills/ and route by the changed files.
3. Read the prior reviews and comments in the bundle. Do not duplicate an open finding.
4. Write /opt/data/review-out/<id>.json using the exact schema in the cr-pr skill.
5. Do not post to GitHub, do not modify the PR, and do not read credentials.
If the script output is NO_READY, respond with exactly [SILENT].'

docker exec -u "$AGENT_UID:$AGENT_GID" -e HOME=/opt/data "$HERMES_CONTAINER" "$HERMES_CLI" cron create "$SCHEDULE" "$prompt" \
  --name "$JOB_NAME" \
  --skill cr-pr \
  --script pr-review-ready.py \
  --deliver local \
  --failure-deliver local \
  --reasoning-effort high
