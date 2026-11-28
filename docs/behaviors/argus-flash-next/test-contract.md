# Flash Next configuration and verification

**Status:** Implementation contract / 2026-11-28.

1. Preserve the current official `strata-flash-next` command and runtime calibration in a host-scoped Home Manager service, imported by Orion.
2. Remove the stale `ai-models` startup and rollout requirements; preserve shared, monitoring, sync, and voice workloads.
3. Rename Discovery's probe to Flash Next; retain `strata_chat_health`, its timestamp, and `/health` for the live Grafana consumer. Publish 1 only for a successful response with `status: ok`, `service: strata`, and `loaded: true`; malformed, unloaded, wrong-service, and transport-error responses publish 0.
4. Preserve the pre-existing unmanaged user unit through the fleet's `backupFileExtension = "backup"`; never force overwrite it.
5. Verify source guards fail before implementation, then pass with existing monitoring checks. Run `just lint`, `just fmt-check`, and `just dry orion` / `just dry discovery`. Full-flake checks belong in CI.

Runtime acceptance after a separately authorized activation: stale Compose unit stopped, official unit loaded from Home Manager and active, `/health` reports `status: ok`, and the corresponding health gauge is 1. This establishes readiness, not generated-answer quality.

Orchestration sets `systemd.user.startServices = false`, so a rebuild alone does not prove that the retired stack stopped or the official unit restarted. The activation steps and rollback boundary belong in the one-pager.
