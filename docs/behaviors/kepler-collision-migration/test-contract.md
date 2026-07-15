# Kepler collision migration test contract

**Status:** Implemented; current desired-state amended after AI-serving retirement

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
| Restate container, `restate_data`, and unshared service image | `retired-wipe` | Exact allowlisted wipe |
| Shared image layer referenced by another container | protected | Leave for normal garbage collection |
| Unknown collision | `halt` | No mutation |

## Static assertions

- The retired wipe allowlist contains only GitLab, Airflow, and Restate resources.
- Legacy `homelab` adoption is limited to stopped `infra` containers with exact
  service, working-directory, config-file, mount, network, image, and source
  provenance; any missing or mismatched field halts.
- GitLab, Airflow, and Restate paths, logical volumes, database, secrets, and images must match the behavior allowlist exactly; parent directories are forbidden wipe targets.
- Declared migration order is exactly `infra`, `ai-serving`, `docs-search`.
- No generated command contains broad `prune`, volume-prune, dataset-destroy, or recursive filesystem deletion outside an exact retired path.
- Every mutating command has a corresponding dry-run rendering.
- Re-running the planner after successful fixtures produces no pending action.
- Registry images without digests and local images/models without immutable provenance halt.
- Compose-required variables and SecretSpec declarations match exactly for each active stack profile.
- GitLab/Airflow/Restate declarations are absent.
- The dry-run manifest is value-free, deterministic, and hash-bound; inventory drift rejects execution.
- Thirty-day retention metadata never emits an automatic snapshot deletion command.

## Failure behavior

Inject failures at each phase:

1. Inventory collection failure: exit before classification.
2. Unknown classification: exit before snapshot or deletion.
3. Retained-database backup/restore failure: no Airflow database drop or retirement wipe.
4. Retired-secret selection or external credential revocation failure: no retirement wipe.
5. PostgreSQL checkpoint, exact stopped legacy Redis reset selection, Qdrant-idle, or MinIO-idle failure: no snapshot or migration. Redis has no backup/restore gate.
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
- Exact current retired-secret declarations and externally valid credential revocations. Historical copies and mixed-backup sanitization are out of scope because GitLab and Airflow were disposable homelab tests.
- Exact Restate container, logical volume, and unshared image selected for wipe.
- SecretSpec value-free resolution and Compose/declaration drift reports.
- Immutable registry, local image, build, and model identities.
- Relevant ZFS datasets and proposed snapshot name.
- Exact stopped legacy `redis` container ID/labels and exact `homelab_redis_data` volume identity, mountpoint, driver, and sole reference selected for manifest-bound reset. The manifest contains no Redis backup/restore action; declarative `infra` recreates desired Redis after the exact reset.
- Dependency-stop, checkpoint, retirement, protection, migration, validation, reboot, retention, and abort commands in execution order.
- Deterministic action-manifest SHA-256 and proof that execution rejects changed inventory.

Any difference between live inventory and fixture assumptions blocks execution and requires a contract update plus a new test run.

The 2026-07-14 retirement adds a focused contract: exactly seven full
container IDs, seven distinct unshared image IDs, and `/fast/ai-models`; both
`infra` and `docs-search` must remain present. Two consecutive inventories
must render the same SHA-256-bound manifest before execution. No network,
volume, broad prune, dataset, snapshot, or parent path is selected.
This supersedes the active three-stack-order, AI immutable-provenance, and AI
route success assertions. Their fixtures remain historical K0/K1 evidence.
The current desired-state assertions require exactly `infra`, then
`docs-search`. Retirement is resumable only at exact stage boundaries: all
seven approved containers, zero approved containers with any subset of the
seven images, zero approved containers/images before exact-path removal, or
everything absent. Image removal and path removal are separate double-inventory
stages. Any survivor bind at, below, or above `/fast/ai-models` halts.
Partial/mismatched containers halt.

## Live success gate

For every replacement, retain evidence of health, clean startup, desired mounts and labels, state checks, endpoint response, dependent smoke tests, and a 15-minute stable observation. Repeat after one Kepler reboot, verify Discovery LiteLLM routes, record Orion checks only when Orion is online, and finish with a read-only second run proving zero remaining collisions or planned mutations. Quarantine deletion is not part of this success gate.
