# Kepler collision migration

**Status:** Approved behavior; K0 complete, K1 read-only inventory blocked pending approval manifest

## Outcome

Recover Kepler's declared rootless-Podman stacks from container-name collisions without improvising on the host. Current services become declarative again. Retired GitLab, Airflow, and Restate state is erased. All three were disposable homelab tests.

## Scope

The migration covers collisions affecting Kepler's declared `infra`, `ai-serving`, and `docs-search` stacks. It also removes retired GitLab, Airflow, and Restate containers, images, cached service-specific layers, named volumes, bind-mounted datasets, database, and secrets.

No broad Podman prune is allowed. Generic image layers still referenced by another container remain. Restate and `restate_data` are exact allowlisted wipe targets; parent datasets and unrelated resources remain protected. Discovery mutations remain frozen until Kepler recovery and reboot validation complete.

## Required behavior

1. Produce a read-only inventory of every Kepler container, Compose label, state, mount, image, network, and owning stack.
2. Classify every name collision before mutation:
   - `retired-wipe`: GitLab, Airflow, or Restate only.
   - `declared-migrate`: a stopped container belonging to `infra`, `ai-serving`, or `docs-search`, with mounts matching the current Compose definition. The known legacy `homelab` project is accepted only for stopped `infra` containers when its service, working-directory, config-file, mount, network, image, and source provenance all match the reviewed legacy contract; every other foreign project halts.
   - `halt`: running, unlabeled, foreign-project, unknown-owner, or mount-mismatched container.
3. Reject an inventory containing any `halt` entry. Never infer ownership from a container name alone.
   A running declared collision may be stopped only by a separate, value-free,
   hash-bound quiesce manifest naming the exact Compose stacks. Re-inventory
   after the approved stop; read-only inventory never stops a workload itself.
4. Before retirement, quiesce shared PostgreSQL and create restore-tested logical backups of every retained database. Fully wipe `retired-wipe` entries before creating the retained-state snapshot. No recovery snapshot is required for GitLab, Airflow, or Restate. The wipe includes their exact containers, service-specific unshared images, named volumes, bind mounts, Airflow database, and secrets.
   - GitLab bind mounts: `/fast/apps/gitlab/config`, `/fast/apps/gitlab/logs`, `/fast/apps/gitlab-runner`, and `/bulk/git`.
   - Airflow bind mounts: `/fast/apps/airflow/dags` and `/fast/apps/airflow/plugins`.
   - Airflow logical volumes: `airflow_logs` and `airflow_config`, resolved from Compose labels rather than an assumed runtime prefix.
   - Airflow database: `airflow` only.
   - Restate logical volume: `restate_data`, resolved from Compose labels rather than an assumed runtime prefix.
   - Secrets: `GITLAB_RUNNER_TOKEN`, `POSTGRES_DB_AIRFLOW`, `AIRFLOW_FERNET_KEY`, `AIRFLOW_SECRET_KEY`, and `AIRFLOW_ADMIN_PASSWORD`.
5. Remove retired secrets from current SecretSpec, SOPS, OpenBao, generated env, and runtime; revoke externally valid credentials. GitLab and Airflow were disposable homelab tests, so K1 does not inventory historical copies, sanitize mixed backups, or rewrite encrypted Git history.
6. Stop dependent workloads and make retained state application-consistent: checkpoint PostgreSQL and confirm Qdrant and MinIO writes are idle. Redis is a disposable cache whose consumers repopulate it; do not back up or restore its legacy data.
7. Restore-test the retained PostgreSQL backup, then create a timestamped recursive ZFS snapshot containing retained state only. The manifest must bind the exact stopped legacy `redis` container and exact `homelab_redis_data` volume for reset; no other container or volume may be selected. During the `infra` slice, remove only those approved Redis resources and let declarative `infra` recreate the desired Redis service and volume. Any other persistent mount outside the snapshot boundary without a verified backup is a `halt`. Thirty days makes the snapshot cleanup-eligible; it does not authorize automatic deletion.
8. Require immutable identity before replacement: registry digest, or local image ID plus source commit/build inputs, and independent model artifact checksum/version where applicable.
9. Process declared stacks in dependency order: `infra`, `ai-serving`, then `docs-search`. Each is a resumable slice with its own ledger. Process one colliding container at a time.
10. Rename each stopped legacy container to `legacy-<name>-<timestamp>`. Start the declarative replacement under the original name.
11. Validate the replacement while retaining its quarantined legacy container. The gate requires:
   - Compose and container health are successful.
   - Startup logs contain no unresolved fatal error.
   - Image, labels, networks, and mounts match the current definition.
   - Stateful data checks pass.
   - The service endpoint is reachable.
   - Dependent-service smoke tests pass.
   - No restart or health regression occurs for 15 minutes.
12. Stop at the first failed gate. Stop the replacement, retain the quarantined container and ZFS snapshot, collect diagnostics, and request explicit restore direction.
13. Never roll back a ZFS dataset automatically. Never restart a legacy container against data mutated by a failed replacement without review.
14. After every slice passes, reboot Kepler through the documented workflow and repeat all gates. Verify Discovery LiteLLM routes to Kepler. Orion checks are opportunistic and non-blocking.
15. Retain non-retired quarantined containers through reboot. Delete them, snapshots, or backups only under a later manifest-bound, exact-resource approval.

## Execution contract

The migration is a committed, idempotent `just` recovery entry point. It has a mandatory dry-run mode and uses only documented remote-action channels. Dry-run produces an immutable, value-free action manifest and SHA-256; execution re-inventories live state and requires approval bound to the matching hash. It must not edit remote configuration files or invoke broad cleanup commands.

The live execution is blocked until Kepler SecretSpec profiles, Compose/declaration drift tests, fixture tests, shell lint, and a read-only Kepler dry run pass. SecretSpec is the contract/preflight layer; SOPS remains bootstrap storage and Vault Agent remains the long-running runtime resolver. The dry-run inventory must exactly match the reviewed allowlists and paths.

## Completion

Recovery is complete only when all declared stacks pass their gates before and after reboot, no name collisions remain, current GitLab/Airflow/Restate resources are absent, retained-state protections exist, Discovery routes work, and a second dry run reports no pending mutation. Cleanup remains a separate approval.
