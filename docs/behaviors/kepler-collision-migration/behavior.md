# Kepler collision migration

**Status:** Approved behavior; implementation not started

## Outcome

Recover Kepler's declared rootless-Podman stacks from container-name collisions without improvising on the host. Current services become declarative again. Retired GitLab and Airflow state is erased. Restate remains an optional standalone Servarr stack.

## Scope

The migration covers collisions affecting Kepler's declared `infra`, `ai-serving`, and `docs-search` stacks. It also removes retired GitLab and Airflow containers, images, cached service-specific layers, named volumes, bind-mounted datasets, database, and secrets.

No broad Podman prune is allowed. Generic image layers still referenced by another container remain. Restate and `restate_data` are explicitly out of the wipe set.

## Required behavior

1. Produce a read-only inventory of every Kepler container, Compose label, state, mount, image, network, and owning stack.
2. Classify every name collision before mutation:
   - `retired-wipe`: GitLab or Airflow only.
   - `declared-migrate`: a stopped container belonging to `infra`, `ai-serving`, or `docs-search`, with mounts matching the current Compose definition.
   - `halt`: running, unlabeled, foreign-project, unknown-owner, or mount-mismatched container.
3. Reject an inventory containing any `halt` entry. Never infer ownership from a container name alone.
4. Fully wipe `retired-wipe` entries. No recovery snapshot is required for GitLab or Airflow. The wipe includes their containers, service-specific images, named volumes, bind mounts, Airflow database, and secrets. Restate is never selected by this rule.
   - GitLab bind mounts: `/fast/apps/gitlab/config`, `/fast/apps/gitlab/logs`, `/fast/apps/gitlab-runner`, and `/bulk/git`.
   - Airflow bind mounts: `/fast/apps/airflow/dags` and `/fast/apps/airflow/plugins`.
   - Airflow logical volumes: `airflow_logs` and `airflow_config`, resolved from Compose labels rather than an assumed runtime prefix.
   - Airflow database: `airflow` only.
   - Secrets: `GITLAB_RUNNER_TOKEN`, `POSTGRES_DB_AIRFLOW`, `AIRFLOW_FERNET_KEY`, `AIRFLOW_SECRET_KEY`, and `AIRFLOW_ADMIN_PASSWORD`.
5. Stop dependent workloads and make remaining state application-consistent: checkpoint Postgres, force a Redis persistence save, and confirm Qdrant and MinIO writes are idle.
6. Copy the Redis named-volume backup into a relevant `/fast` dataset, then create a recursive ZFS snapshot tagged `pre-kepler-collision-migration`. Any persistent mount outside the snapshot boundary without a verified backup is a `halt`. Retain the snapshot for 30 days after successful recovery.
7. Process declared stacks in dependency order: `infra`, `ai-serving`, then `docs-search`. Process one colliding container at a time.
8. Rename each stopped legacy container to `legacy-<name>-<timestamp>`. Start the declarative replacement under the original name.
9. Validate the replacement before deleting its quarantined legacy container. The gate requires:
   - Compose and container health are successful.
   - Startup logs contain no unresolved fatal error.
   - Image, labels, networks, and mounts match the current definition.
   - Stateful data checks pass.
   - The service endpoint is reachable.
   - Dependent-service smoke tests pass.
   - No restart or health regression occurs for 15 minutes.
10. Stop at the first failed gate. Stop the replacement, retain the quarantined container and ZFS snapshot, collect diagnostics, and request explicit restore direction.
11. Never roll back a ZFS dataset automatically. Never restart a legacy container against data mutated by a failed replacement without review.
12. Delete the quarantined legacy container only after its replacement passes every gate.

## Execution contract

The migration is a committed, idempotent `just` recovery entry point. It has a mandatory dry-run mode and uses only documented remote-action channels. It must not edit remote configuration files or invoke broad cleanup commands.

The live execution is blocked until fixture tests, shell lint, and a read-only Kepler dry run pass. The dry-run inventory must exactly match the reviewed allowlists and paths.

## Completion

Recovery is complete only when all declared stacks pass their gates, no name collisions remain, retired GitLab/Airflow state is absent, Restate state remains, the ZFS snapshot exists with its expiry metadata, and a second dry run reports no pending mutation.
