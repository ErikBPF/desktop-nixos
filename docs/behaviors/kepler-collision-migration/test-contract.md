# Kepler collision migration test contract

**Status:** Approved contract; tests not implemented

## Test boundary

Tests validate classification and command planning without contacting Kepler. Live preflight then validates the same planner against read-only host inventory. Mutation is a separate, explicitly invoked phase.

## Fixture matrix

The test suite must cover:

| Fixture | Expected classification | Expected action |
|---------|-------------------------|-----------------|
| Stopped declared container; labels and mounts match | `declared-migrate` | Quarantine, replace, validate, then delete legacy container |
| Running declared container | `halt` | No mutation |
| Stopped container with missing Compose labels | `halt` | No mutation |
| Foreign Compose project | `halt` | No mutation |
| Declared name with mount mismatch | `halt` | No mutation |
| GitLab container, bind mounts, volumes, and image | `retired-wipe` | Exact allowlisted wipe |
| Airflow containers, database, bind mounts, volumes, and image | `retired-wipe` | Exact allowlisted wipe |
| Restate container or `restate_data` | protected | No wipe or migration unless independently colliding |
| Shared image layer referenced by another container | protected | Leave for normal garbage collection |
| Unknown collision | `halt` | No mutation |

## Static assertions

- The retired wipe allowlist contains only GitLab and Airflow resources.
- The protected list contains Restate and `restate_data`.
- GitLab and Airflow paths, logical volumes, database, secrets, and images must match the behavior allowlist exactly; parent directories are forbidden wipe targets.
- Declared migration order is exactly `infra`, `ai-serving`, `docs-search`.
- No generated command contains broad `prune`, volume-prune, dataset-destroy, or recursive filesystem deletion outside an exact retired path.
- Every mutating command has a corresponding dry-run rendering.
- Re-running the planner after successful fixtures produces no pending action.

## Failure behavior

Inject failures at each phase:

1. Inventory collection failure: exit before classification.
2. Unknown classification: exit before snapshot or deletion.
3. Postgres checkpoint, Redis save/backup, Qdrant-idle, or MinIO-idle failure: no snapshot or migration.
4. Unprotected persistent mount or ZFS snapshot failure: no declared-container mutation.
5. Replacement start failure: legacy container remains quarantined; halt.
6. Health, log, mount, state, endpoint, smoke, or observation failure: stop replacement, retain legacy and snapshot, halt.
7. Legacy deletion failure after a successful gate: report incomplete cleanup without rolling back the healthy replacement.
8. Second-run fixture: completed resources are recognized and skipped.

No failure path may automatically roll back a dataset or start a legacy container against possibly changed state.

## Live dry-run gate

Before execution, the read-only run must record sanitized evidence for:

- Container IDs, states, images, labels, mounts, networks, and stack ownership.
- Exact collisions and their classification.
- Exact GitLab/Airflow containers, paths, volumes, database, images, and cached layers selected for wipe.
- Proof that Restate resources are excluded.
- Relevant ZFS datasets and proposed snapshot name.
- Redis named-volume backup destination and proof that every persistent mount is inside the snapshot boundary or independently backed up.
- Dependency-stop, checkpoint, migration, validation, quarantine-deletion, and abort commands in execution order.

Any difference between live inventory and fixture assumptions blocks execution and requires a contract update plus a new test run.

## Live success gate

For every replacement, retain evidence of health, clean startup, desired mounts and labels, state checks, endpoint response, dependent smoke tests, and a 15-minute stable observation. Finish with a read-only second run proving zero remaining collisions or planned mutations.
