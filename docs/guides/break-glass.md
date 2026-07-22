# Break-glass recovery

**Status:** Guide — value-free recovery index; tested runbooks and `justfile`
recipes remain authoritative.

Use this page when normal deployment or secret delivery is unavailable. It
chooses the recovery path; it does not duplicate credentials or destructive
OpenBao commands. If this guide and a recipe disagree, the recipe wins.

## Safety boundary

- Preserve evidence before changing state: time, failing unit, Git revision,
  generation, and value-free logs.
- Never print, paste into chat, or commit decrypted values, tokens, unseal keys,
  provider files, or `.env` contents.
- Do not edit a remote checkout or host configuration over SSH. Recover through
  the owning repository and documented `just` entry point.
- Do not rotate, revoke, delete, reseal, restore, roll back a disk, or destroy a
  volume until service recovery is stable and the destructive action is
  explicitly approved.
- Prefer IP or tailnet access during DNS incidents. Do not make DNS recovery
  depend on the failed resolver.

## First five minutes

1. Stop automated retries if they are increasing impact. Do not stop healthy
   dependencies merely to make the incident uniform.
2. Identify the failed boundary: deployment, one Compose stack, Vault Agent,
   OpenBao, DNS/network, host/PID1, or total host loss.
3. Record the current source revisions and unit state without reading secret
   values.
4. Follow exactly one path below. Escalate to disaster recovery only when the
   narrower recovery path is disproven.
5. After recovery, run the named verification and retain the old provider,
   generation, snapshot, or encrypted source until the observation gate closes.

## Decision table

| Symptom | Recovery path | Success proof |
| --- | --- | --- |
| A deployment loses connectivity | Let deploy-rs magic rollback finish. Re-evaluate the intended revision with `just dry <host>` before another `just switch-<host>`. | Deployment confirmed; SSH/tailnet reachable; affected services checked. |
| One Servarr stack fails | `just diagnose-stack <host> <stack>`. Fix in the Servarr repo, commit and push, then `just pull-servarr <host>` and `just kick-stack <host> <stack>`. | Unit active; intended container health/integration probe passes. |
| SecretSpec stack fails before Compose | Check the unit with `just diagnose-stack`, then identify the profile's declared sources in `secretspec.toml`. For Vault-backed names, verify or refresh Vault Agent with the documented recipe. For SOPS-backed names, restore the encrypted Servarr source through Git and `just pull-servarr <host>`. Mixed profiles require both providers. Recreate only the affected stack. | Every declared provider is healthy; SecretSpec preflight and targeted health gate pass. |
| SecretSpec regression after a cutover | Revert the versioned desktop-nixos cutover, run `just dry discovery`, deploy with `just switch-discovery`, then `just kick-stack discovery <stack>`. Keep Vault Agent and its render intact. | Direct-Compose rollback unit active; service health matches pre-cutover evidence. |
| OpenBao is sealed | Follow [Vault disaster recovery — Scenario A](../reference/vault-disaster-recovery.md#scenario-a--node-sealed-reboot--restart). Do not initialize a new cluster. | `Initialized=true`, `Sealed=false`; consumers re-sync. |
| OpenBao data is corrupt or missing | Follow [Vault disaster recovery — Scenario B](../reference/vault-disaster-recovery.md#scenario-b--data-corrupt--lost-host-intact). Snapshot restore is destructive and needs explicit approval. | Known-path read succeeds without logging its value; fresh backup succeeds. |
| Discovery/OpenBao is totally lost | Follow [Vault disaster recovery — Scenario C](../reference/vault-disaster-recovery.md#scenario-c--total-loss-rebuild-discovery-from-zero). Recover the offline age key first. | Old barrier unsealed; consumers re-sync; backup and alert return healthy. |
| Primary age key is unavailable | Use the off-fleet escrow described in [key rotation](../reference/key-rotation.md) and [Vault disaster recovery](../reference/vault-disaster-recovery.md#prerequisite--the-one-thing-dr-depends-on). Do not rotate during recovery. | SOPS decrypts on a controlled recovery machine; key is not exposed in logs. |
| DNS is unavailable | Reach fleet hosts by `fleet.json` IP or the unaffected overlay. Restore the resolver through its owning repo and documented recipe. | Client lookup and direct service probe both pass. |
| PID1/network is frozen | Follow [frozen PID1 recovery](../reference/recovery-frozen-pid1.md). Forced reboot steps are last-resort and physical/destructive actions require operator presence. | Host returns on SSH; filesystems and critical units are healthy. |
| Credential compromise is suspected | Contain access without deleting recovery material. Inventory affected authority/provider/consumers, restore service, then follow [key rotation](../reference/key-rotation.md). | Replacement credential works; old credential revoked only after consumers converge. |

## SecretSpec and Vault Agent triage

The Vault-backed runtime chain is:

```text
OpenBao authority -> Vault Agent render -> SecretSpec process environment
  -> Docker Compose -> container
```

Diagnose left to right. A missing/unreadable/stale render is a provider problem;
a failed SecretSpec preflight is an execution-boundary problem; a healthy start
followed by an unhealthy target is an application problem. Do not bypass
SecretSpec by adding the provider file directly to Compose unless executing the
reviewed rollback revision.

SOPS-only profiles do not depend on Vault Agent. Recover their encrypted source
through the Servarr Git delivery flow, then recreate the affected stack. Mixed
profiles need both the SOPS source and Vault Agent render healthy; restoring one
provider does not make the profile complete. Use the profile declarations in
`secretspec.toml` as the source-closure authority instead of guessing from the
stack name.

For the Discovery tools pilot, expected metadata is `0440 root:docker`, the
declared name set contains only `SEARXNG_SECRET_KEY`, and SearXNG is the targeted
health gate. Never inspect or compare the value in terminal output.

## Recovery completion checklist

- Source and deployed revisions recorded.
- Recovery used repository-owned `just` recipes.
- Unit active and target-specific health/integration check passed.
- No secret value appeared in terminal, logs, issue, PR, or evidence.
- Backup/provider health verified when the incident involved OpenBao or SOPS.
- Rollback material retained through the observation window.
- Incident cause and any stale documentation recorded before normal automation
  resumes.

## Authoritative references

- [OpenBao disaster recovery](../reference/vault-disaster-recovery.md)
- [Fleet key rotation](../reference/key-rotation.md)
- [Frozen PID1 recovery](../reference/recovery-frozen-pid1.md)
- [Vault backup implementation](../implemented/2026-06-29-vault-backup-plan.md)
- [Offsite crown-jewel recovery](../implemented/2026-06-30-offsite-dr-crown-jewels.md)
