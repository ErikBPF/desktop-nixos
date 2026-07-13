# Stateful stack release hardening — execution plan

**Status:** In progress — P0 complete; P1 staged at the explicit SWAG
container-replacement approval gate.

## 1. Purpose and authority

This is the operator execution plan for
[`2026-07-13-stateful-stack-release-hardening.md`](2026-07-13-stateful-stack-release-hardening.md).
It is written for a fresh operator continuing the rollout without chat history.
The proposal's locked decisions, phase order, ownership boundaries, safety
constraints, verification contracts, and acceptance criteria remain
authoritative. If this plan conflicts with the proposal, the proposal wins. If
an operational document conflicts with a `just` recipe, the recipe wins and the
document must be corrected.

| Repository | Ownership |
|---|---|
| `desktop-nixos` | Discovery host orchestration, fixed migration workflows, release agent, monitoring |
| `servarr` | Discovery Compose stacks, physical volumes, immutable workload pins |
| `homelab-iac` | AdGuard and Cloudflare Terraform, wired-LAN plans and applies |
| `kindle-dash` | Tests, protected-main releases, SemVer, signing, SBOM and provenance |

Leaf repositories land first. Consumers and host orchestration follow only
after the leaf commit is published and pinned.

## 2. Current state

### P0 — complete

- Servarr `98ecafb` records migration debt and rejects new implicit or anonymous
  state volumes.
- Desktop `50454f9`, `6217215`, and `061a1cc` provide ledger-gated inventory,
  snapshot, archive, restore, compare, smoke, rollback-evidence, and orphan
  tooling.
- The disposable fixture passed using servarr `312fa76` and digest
  `sha256:ce148c3794d2dfcb63eaeed55c516324e800349f8cd57e49ec0eb312fe75f01d`.
- Read-only snapshot
  `/home/.snapshots/stateful-stack-p0-fixture-20260713` has UUID
  `342edcd9-15a8-0448-8822-3347328d0ff2`.
- Archive checksum/read and restored byte, ownership, mode, ACL, and xattr
  comparisons passed. All fixture resources remain retained.
- P0 completion evidence is in desktop `5a24439`.

### P1 — staged, not yet mutated

- Servarr `c2b0714` pins SWAG and `swag-init` to observed immutable digests;
  discovery has pulled it.
- Desktop `3bbefaf` installs fixed workflow
  `discovery-stateful-swag-adopt.service`. It is disabled and has not run.
- SWAG is healthy under project `networking`, owner
  `/home/erik/servarr/machines/discovery`, with its only state bind mounted at
  `/config`.
- The bind measured `18,049,624` bytes, owner `1000:1000`.
- Pre-change nginx, ingress, and certificate checks pass. `cloudflare.ini` is
  unexpectedly `0644`; P1 requires `0600` after recreation and fails otherwise.
- Current gate: replacing containers `swag` and `swag-init` requires explicit
  approval. P1 deletes no volume, snapshot, backup, or state.

### Known later gates

- P3: vanguard CoreDNS works over Tailscale, but LAN DHCP advertises only the
  UDM. Generic LAN clients lack a secondary fleet resolver.
- P4: `gmichels/adguard` `v1.7.0` previously failed an update with DHCP
  disabled. A disposable lifecycle proof or provider fix is required. The IaC
  repository also contains unrelated dirty work that must be isolated.
- P5: empty `discovery_adguard_work` already collides with the canonical name.
  It cannot be reused or deleted without proof and explicit approval.
- P6: kindle-dash `main` is unprotected; releases are tag-only and unsigned;
  no scoped GitHub App credentials exist for verified servarr pin PRs.

## 3. Non-negotiable rules

1. Execute P0–P9 in order. Later phases may be inspected, not mutated, before
   their predecessor completes.
2. Re-read repository instructions/runbooks and re-inspect live state before
   every slice.
3. Preserve unrelated dirty work. Stage only active-slice files.
4. Before workload mutation, persist commit, container/project/owner, image
   tag/digest, physical storage/mount, size/ownership, backup identifiers,
   rollback command, and downtime estimate.
5. Adopt existing state in place before canonical copying.
6. Never delete a container, volume, snapshot, backup, or remote state without
   current-turn approval naming that resource.
7. Keep legacy volumes through smoke tests and one discovery reboot. Databases
   also require a successful backup cycle.
8. Mutate discovery only through documented `just` recipes or fixed approved
   systemd workflows. Never edit remote files.
9. Apply Terraform only from wired LAN, using an inspected saved plan and live
   post-apply probes. Stop on unexplained drift.
10. Deploy immutable image digests; never `latest`.
11. Stop on checksum mismatch, missing backup, ownership ambiguity, unexplained
    drift, or rollback failure.
12. Never weaken tests, health gates, branch protection, signature validation,
    or security boundaries.

## 4. Per-slice contract

1. State assumptions, repositories, risk, downtime, rollback, and verification.
2. Capture failing tests or observable pre-change evidence where practical.
3. Make the smallest owner-local change.
4. Run repository-local format, lint, tests, and config evaluation.
5. Commit/publish the leaf repository, then pin it in the consumer.
6. Write the complete ledger before workload mutation.
7. Stop only affected services; snapshot and checksum/archive state.
8. Prove archive read/restore/compare before irreversible change.
9. Mutate through the approved recipe or systemd workflow.
10. Run hard smoke gates and inspect logs/metrics.
11. Verify rollback evidence before removing old protection.
12. Record exact commits, digests, volumes, snapshots, plans, probes, and risks.

Desktop final gates:

```bash
just lint
just fmt-check
just dry discovery
```

Run `just check` for shared/fleet behavior and `just docs-check` for docs.

## 5. Ordered phase plan

### P0 — audit and safety tooling — complete

Delivered: live owner/state inventory; state impact classification; servarr
explicit-volume policy and fixtures; ledger/snapshot/archive/restore/compare/
smoke/rollback/orphan helpers; retained disposable live proof; exact evidence.
No fixture cleanup is authorized.

### P1 — SWAG in-place adoption — active

#### P1.1 Immutable pins — complete

- SWAG:
  `lscr.io/linuxserver/swag:5.6.0-ls467@sha256:ce148c3794d2dfcb63eaeed55c516324e800349f8cd57e49ec0eb312fe75f01d`
- Init:
  `busybox:1.38@sha256:fd8d9aa63ba2f0982b5304e1ee8d3b90a210bc1ffb5314d980eb6962f1a9715d`
- Compose render, digest assertions, and state-volume tests passed.

#### P1.2 In-place adoption — approval gate

After approval naming `swag` and `swag-init`:

1. Start the fixed SWAG adoption service.
2. Confirm ledger precedes stop; verify `/home` snapshot and bind archive.
3. Recreate only init/SWAG through fixed Compose arguments.
4. Require exact digest/project/owner/bind, healthy state, no restart loop.
5. Require credential mode `0600`, expected owner, non-empty secret without
   logging it.
6. Run nginx config, wildcard SAN/expiry, Certbot DNS-01 dry-run gates.
7. Probe Grafana `200`, AdGuard `302`, and LAN Kindle `/dash.png` PNG.
8. Persist downtime, snapshot UUID, archive checksum, certificate fingerprint,
   and rollback evidence. Retain everything.

On hard failure, stop; do not delete evidence. Execute the ledger rollback and
repeat gates.

#### P1.3 Reboot persistence

Reboot only through documented host workflow. Verify unit ownership, health,
digest/mount, ingress, certificate, DNS-01, and Kindle route. Record generation
and probes; then close P1.

### P2 — AdGuard in-place adoption

1. Refresh API/config/filter/query-log/exporter baseline.
2. Record `networking_adguard_work`, immutable digest, size, `65534:65534`
   owner, mode, and mount.
3. In servarr, declare that existing physical volume explicitly as external;
   do not copy it.
4. Prove rendered Compose still resolves to that physical volume.
5. Ledger, stop AdGuard/dependent exporter, snapshot config, archive work, and
   prove restore/compare.
6. Recreate without copy and compare LAN query, fleet rewrite, external lookup,
   blocked response, API, filters, query log, stats, rewrites, user rules, and
   exporter.
7. Verify rollback to the same physical mapping; retain state.

### P3 — secondary fleet DNS

1. Reconfirm DHCP resolvers and vanguard listeners/routes.
2. Design a LAN-reachable secondary that resolves fleet and external names;
   public DNS is forbidden as normal fallback.
3. Land network ownership in homelab-iac and host support in desktop-nixos.
4. Create/inspect saved plan from wired LAN; stop on unrelated drift.
5. Apply and probe from a generic LAN client.
6. Stop AdGuard through approved workflow; prove fleet/external resolution via
   secondary; restore and verify both resolvers.

### P4 — full AdGuard Terraform ownership

#### Provider admission

1. Isolate unrelated homelab-iac dirty work.
2. Exact-pin provider and verify lockfile.
3. Reproduce disabled-DHCP lifecycle against disposable target.
4. Fix or reject provider if full create/read/update/delete is unsafe. Never
   omit supported settings merely to avoid the bug.

#### Export, model, import

1. Export full API state and YAML rollback copy without committing secrets.
2. Model every supported DNS/cache/rate/block/client/PTR/filter/rewrite/rule/
   query/stat/safe-service/schedule/DHCP/lease/TLS setting.
3. Import existing resources and require zero unexplained drift after refresh,
   restart, and runtime activity.
4. Add provider tests and manual recovery.

#### Wired saved-plan apply

1. Prefetch; capture baseline probes; create/checksum/inspect saved plan.
2. Apply only that plan while probing LAN DNS, fleet rewrite, external lookup,
   blocked response, and API.
3. Auto-restore YAML and prior Terraform state/config within five minutes on
   critical failure.
4. Remove overlapping servarr declarations only after green apply/zero drift.

### P5 — canonical AdGuard volume

1. Resolve empty `discovery_adguard_work` collision without unauthorized reuse
   or deletion.
2. Create approved `discovery-adguard-work`.
3. Ledger, stop AdGuard, fresh snapshot/archive, verify backup.
4. Copy metadata-preserving; compare source/destination; stop on delta.
5. Update explicit mapping, recreate, repeat P2/P4 probes.
6. Reboot discovery and repeat probes.
7. Retain `networking_adguard_work` and all protection.

### P6 — kindle-dash protected automatic releases

#### Tests and release semantics

1. Add deterministic PNG and Claude/Codex/opencode parser fixtures.
2. Test minor default, patch, major, none, and conflicting labels.
3. Protect `main`: PR-only, required CI, no force pushes, owner bypass.
4. Create mutually exclusive release labels.

#### Signed publication

1. Build amd64 from protected merge commit and calculate SemVer from latest
   valid tag.
2. Publish immutable GHCR digest; generate SBOM/provenance.
3. Cosign keyless with expected repo/workflow identity; verify all artifacts.

#### Verified servarr pin

1. Provision narrow GitHub App.
2. Open single-file tag/digest PR.
3. Require tag existence, signature identity, immutable digest, Compose render,
   and state-volume checks; auto-merge only green.

#### Pull-based discovery promotion

1. Fixed root agent; no arbitrary repo/stack/command/path/tag/image input.
2. Verify signed GHCR metadata; mirror exact digest to scoped Harbor; prove
   parity and merged servarr pin.
3. Pull via documented service; recreate managed kindle stack.
4. Gate running digest, owner, volume, health, and PNG.

#### Rollback and reporting

1. Force hard-gate failure; prove automatic old pin/image restoration without
   touching volume.
2. Force provider-auth failure; prove degraded-only status.
3. Interrupt each persisted phase; prove safe resume after revalidation.
4. Align atomic state, systemd, Alloy, metrics, GitHub, and Discord on identical
   version/digest/phase/failure/rollback.

### P7 — remaining stateful stacks

One service or tightly coupled DB group per slice: explicit adopt/recreate,
snapshot/archive/copy/compare, canonical switch/recreate, smoke, reboot, retain.

1. PostgreSQL, Redis, OpenBao consumers, Vaultwarden, MinIO, ClickHouse and DB
   state. Require app dumps and successful backup cycle before cleanup.
2. Plex, Jellyfin, Jellystat, Tautulli, arr/media metadata.
3. Grafana, Prometheus, Loki, healthchecks, Scrutiny, other tools.
4. Cache/rebuildable volumes only after regeneration proof.

Anonymous/zero-link/zero-byte resources are not proven orphans.

### P8 — Terraform control-plane inventory

Inventory Grafana, Harbor, PocketID, MinIO, Cloudflare, GitHub, NetBird,
Tailscale, and UniFi. Prefer official/stable `>=1.0`; otherwise require exact
pin/lock, import, zero diff, API export, tests, and manual recovery. Move only
control-plane objects. Keep containers/filesystem state with existing owners.
Keep applies wired, saved-plan, and human-gated. Output a provider admission
decision table with direct evidence.

### P9 — orphan report and deletion approvals

1. Re-inventory after migrations and reboot.
2. Prove no active owner/mount and no unique state or verified backup.
3. Report resource, size, owner, last consumer, backup, retention gate, and
   exact deletion command.
4. Request separate approval for every container, volume, snapshot, archive,
   or remote-state deletion.
5. Delete approved resources one at a time; re-run probes each time.

Protected candidates include `kindle-dash_kindle_dash_data`, colliding
`discovery_adguard_work`, P0 fixture resources, and retained legacy volumes.
Presence alone is not orphan proof.

## 6. Verification matrix

| Surface | Required evidence |
|---|---|
| Desktop | lint, fmt-check, discovery dry-build; full check for shared behavior; post-switch probes |
| Servarr | Compose render, exact digest, volume policy/fixtures, service smoke |
| IaC | format, validate, lock consistency, security, saved plan/checksum, import/zero diff, wired probes |
| Kindle | format/lint, parser fixtures, PNG, image build, SemVer labels, signature/SBOM/provenance |
| Migration | ledger, stopped-service backup, checksum/read/restore/compare, identity/health, rollback, reboot |
| SWAG | nginx, cert SAN/expiry, DNS-01 dry run, HTTPS, LAN PNG, clean logs |
| AdGuard | LAN A/AAAA, rewrite, external, blocked, API, filters/log/stats/rules/exporter, secondary outage |
| Release | signed digest, owner/volume/health/PNG, forced rollback, degraded failure, resume, consistent reporting |

No phase completes without fresh verification output after its final change and
live mutation.

## 7. Approval and credential gates

Stop and request only the narrow missing authority for:

- named container replacement/deletion;
- named volume/snapshot/backup/fixture/remote-state deletion;
- destructive rollback;
- non-wired Terraform apply, unexplained drift, or saved-plan mismatch;
- missing Cloudflare, AdGuard, GitHub App, Cosign/OIDC, Harbor, GitHub status, or
  Discord credentials;
- unapproved GitHub branch-protection/repository-setting changes;
- ambiguous ownership or missing/failed backup.

Current gate: approve replacement of `swag` and `swag-init` for P1.2. This does
not authorize deletion of bind state, volumes, P0 fixtures, P1 protection, or
legacy resources.

## 8. Completion ledger

| Phase | State | Evidence | Remaining gate |
|---|---|---|---|
| P0 | Complete | Servarr `98ecafb`; desktop `50454f9`, `6217215`, `061a1cc`, `5a24439`; retained fixture | P9 cleanup only |
| P1 | In progress | Servarr `c2b0714`; desktop `3bbefaf`; live preflight | Approval for `swag`, `swag-init` replacement |
| P2 | Pending | — | P1 complete |
| P3 | Pending | Read-only audit | P2; LAN-reachable design |
| P4 | Pending | Read-only audit | P3; clean IaC scope; lifecycle proof |
| P5 | Pending | Collision inventory | P4; collision resolution |
| P6 | Pending | Read-only release audit | P5; settings/credentials |
| P7 | Pending | P0 inventory | P6; per-service ledgers |
| P8 | Pending | — | P7 |
| P9 | Pending | Candidate inventory | P8; per-resource approvals |

Completion requires direct, current evidence for all eleven acceptance criteria
in the authoritative proposal and no remaining required work.
