# Kepler collision migration test contract

**Status:** Approved contract; K0 fixture tests implemented, K1 live dry-run pending

## Test boundary

Tests validate classification and command planning without contacting Kepler. Live preflight then validates the same planner against read-only host inventory. Mutation is a separate, explicitly invoked phase.

## Fixture matrix

The test suite must cover:

| Fixture | Expected classification | Expected action |
|---------|-------------------------|-----------------|
| Stopped declared container; labels and mounts match | `declared-migrate` | Quarantine, replace, validate, retain through reboot |
| Running declared container | `halt` | No mutation |
| Stopped container with missing Compose labels | `halt` | No mutation |
| Foreign Compose project | `halt` | No mutation |
| Stopped legacy `homelab` infra container with exact provenance labels, mounts, networks, and image | `declared-migrate` | Quarantine only after approval |
| Declared name with mount mismatch | `halt` | No mutation |
| GitLab container, bind mounts, volumes, and image | `retired-wipe` | Exact allowlisted wipe |
| Airflow containers, database, bind mounts, volumes, and image | `retired-wipe` | Exact allowlisted wipe |
| Restate container or `restate_data` | protected | No wipe or migration unless independently colliding |
| Shared image layer referenced by another container | protected | Leave for normal garbage collection |
| Unknown collision | `halt` | No mutation |

## Static assertions

- The retired wipe allowlist contains only GitLab and Airflow resources.
- Legacy `homelab` adoption is limited to stopped `infra` containers with exact
  service, working-directory, config-file, mount, network, image, and source
  provenance; any missing or mismatched field halts.
- The protected list contains Restate and `restate_data`.
- GitLab and Airflow paths, logical volumes, database, secrets, and images must match the behavior allowlist exactly; parent directories are forbidden wipe targets.
- Declared migration order is exactly `infra`, `ai-serving`, `docs-search`.
- No generated command contains broad `prune`, volume-prune, dataset-destroy, or recursive filesystem deletion outside an exact retired path.
- Every mutating command has a corresponding dry-run rendering.
- Re-running the planner after successful fixtures produces no pending action.
- Registry images without digests and local images/models without immutable provenance halt.
- Compose-required variables and SecretSpec declarations match exactly for each active stack profile.
- GitLab/Airflow declarations are absent; Restate declarations remain protected.
- The dry-run manifest is value-free, deterministic, and hash-bound; inventory drift rejects execution.
- Thirty-day retention metadata never emits an automatic snapshot deletion command.

## Failure behavior

Inject failures at each phase:

1. Inventory collection failure: exit before classification.
2. Unknown classification: exit before snapshot or deletion.
3. Retained-database backup/restore failure: no Airflow database drop or retirement wipe.
4. Retired-secret revocation, mixed-backup sanitization, or exact artifact selection failure: no historical artifact deletion.
5. Postgres checkpoint, Redis save/backup/restore, Qdrant-idle, or MinIO-idle failure: no snapshot or migration.
6. Unprotected persistent mount or ZFS snapshot failure: no declared-container mutation.
7. Replacement start failure: legacy container remains quarantined; halt.
8. Health, log, mount, state, endpoint, smoke, observation, or reboot failure: stop further slices, retain legacy and snapshot, halt.
9. Cleanup-manifest mismatch: retain every quarantine and protection artifact.
10. Second-run fixture: completed resources are recognized and skipped.

No failure path may automatically roll back a dataset or start a legacy container against possibly changed state.

## Live dry-run gate

Before execution, the read-only run must record sanitized evidence for:

- Container IDs, states, images, labels, mounts, networks, and stack ownership.
- Exact collisions and their classification.
- Exact GitLab/Airflow containers, paths, volumes, database, images, and cached layers selected for wipe.
- Exact current and non-Git historical retired-secret artifacts, revocations, sanitized replacements, and restore/compare evidence.
- Proof that Restate resources are excluded.
- SecretSpec value-free resolution and Compose/declaration drift reports.
- Immutable registry, local image, build, and model identities.
- Relevant ZFS datasets and proposed snapshot name.
- Redis named-volume backup destination and proof that every persistent mount is inside the snapshot boundary or independently backed up.
- Dependency-stop, checkpoint, retirement, protection, migration, validation, reboot, retention, and abort commands in execution order.
- Deterministic action-manifest SHA-256 and proof that execution rejects changed inventory.

Any difference between live inventory and fixture assumptions blocks execution and requires a contract update plus a new test run.

## Live success gate

For every replacement, retain evidence of health, clean startup, desired mounts and labels, state checks, endpoint response, dependent smoke tests, and a 15-minute stable observation. Repeat after one Kepler reboot, verify Discovery LiteLLM routes, record Orion checks only when Orion is online, and finish with a read-only second run proving zero remaining collisions or planned mutations. Quarantine deletion is not part of this success gate.
