#!/usr/bin/env bash
# Install the claim probe and create one Hermes cron job per worker. Idempotent.
set -euo pipefail

: "${HERMES_CONTAINER:=hermes-daedalus}"
: "${HERMES_CLI:=/opt/hermes/.venv/bin/hermes}"
: "${DATA_DIR:?DATA_DIR is required}"
: "${CLAIM_SCRIPT:?CLAIM_SCRIPT is required}"
: "${AGENT_UID:=10000}"
: "${AGENT_GID:=10000}"
: "${JOB_NAME:=hermes-pr-review}"
: "${SCHEDULE:=*/10 * * * *}"
: "${PARALLELISM:=1}"

install -d -o "$AGENT_UID" -g "$AGENT_GID" -m 0755 "$DATA_DIR/scripts" "$DATA_DIR/review-claims"
install -m 0755 -o "$AGENT_UID" -g "$AGENT_GID" "$CLAIM_SCRIPT" \
  "$DATA_DIR/scripts/pr-review-claim.py"

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

prompt='The script output is either NO_CLAIM or CLAIM <id>. If NO_CLAIM, respond with exactly [SILENT] and do nothing else.
For the claimed bundle:
1. Read /opt/data/review-in/<id>/request.md and meta.json.
2. Load the base-pinned skills in /opt/data/review-in/<id>/skills/ and route by the changed files.
3. Read the prior reviews and comments in the bundle. Do not duplicate an open finding.
4. Read repo-context.md for earlier reviews in the same repository. It is the only cross-PR background you may use; ignore anything from another repository.
5. Write /opt/data/review-out/<id>.json using the exact schema in the cr-pr skill.
6. Do not post to GitHub, do not modify the PR, and do not read credentials.
Review only that one bundle and finish; other workers own the rest.'

job_id() {
  awk -v want="$1" '
    $1 == "Name:" && $2 == want { print id; exit }
    /^[[:space:]]*[0-9a-f]+[[:space:]]+\[/ { id = $1 }
  ' "$list_file"
}

for i in $(seq 1 "$PARALLELISM"); do
  name="$JOB_NAME-$i"
  id="$(job_id "$name")"
  if [ -n "$id" ]; then
    # Reconcile an existing worker to the current prompt and script.
    docker exec -u "$AGENT_UID:$AGENT_GID" -e HOME=/opt/data "$HERMES_CONTAINER" "$HERMES_CLI" cron edit "$id" \
      --schedule "$SCHEDULE" \
      --prompt "$prompt" \
      --script pr-review-claim.py \
      --no-continuity >/dev/null
    continue
  fi
  docker exec -u "$AGENT_UID:$AGENT_GID" -e HOME=/opt/data "$HERMES_CONTAINER" "$HERMES_CLI" cron create "$SCHEDULE" "$prompt" \
    --name "$name" \
    --skill cr-pr \
    --script pr-review-claim.py \
    --deliver local \
    --failure-deliver local \
    --reasoning-effort high
done

# Retire the single pre-parallel job whenever it exists: the new worker is
# always installed as $JOB_NAME-1, and the legacy job still carries the old
# READY prompt, so keeping it would double-review bundles.
old_id="$(job_id "$JOB_NAME")"
if [ -n "$old_id" ]; then
  docker exec -u "$AGENT_UID:$AGENT_GID" -e HOME=/opt/data "$HERMES_CONTAINER" "$HERMES_CLI" cron remove "$old_id" || true
fi

# The legacy script would let a resurrected job review without claims.
rm -f "$DATA_DIR/scripts/pr-review-ready.py"

# Retire workers above the configured parallelism, so lowering the option does
# not leave orphan jobs claiming bundles.
awk -v base="$JOB_NAME" -v max="$PARALLELISM" '
  $1 == "Name:" && $2 ~ ("^" base "-[0-9]+$") {
    n = $2
    sub("^" base "-", "", n)
    if (n + 0 > max) print id
  }
  /^[[:space:]]*[0-9a-f]+[[:space:]]+\[/ { id = $1 }
' "$list_file" | while read -r orphan; do
  [ -n "$orphan" ] || continue
  docker exec -u "$AGENT_UID:$AGENT_GID" -e HOME=/opt/data "$HERMES_CONTAINER" "$HERMES_CLI" cron remove "$orphan" || true
done
