# Harbor publisher bootstrap: controller-only capture

**Status:** Source/TDD prepared; independent review, publication, merge, and live
capture pending. No SecretID has been issued by this change.

## Outcome and human seed

The operator selected **“Controller-only repair (Recommended)”**. The supplied
scope is preserved verbatim: “Preserve RoleID/roles/policies ALLreader/Cognee
credentials/state. NObulk capture/hostdeployment/consumerrestart.” Source PR and
merge are authorized, followed by exactly one replacement SecretID for the
existing IaC fleet-publisher controller. This preparation stage does not execute
that authorization: the parent must review and merge the source before capture.

Earlier read-only provisioning preflight found Harbor 2.15.2, no HA project or
named publisher collision, and an absent exact HA Vault metadata path. The
existing controller RoleID matched its live AppRole, but authentication failed.
The bounded exact stored-SecretID lookup returned HTTP 204 with an empty body.
That is not successful credential metadata; validity and the reason for failure
remain unresolved. Do not describe the old SecretID as expired or revoked.

## Changes and decisions

`just capture-harbor-fleet-publisher-secret-id` calls the
[fixed-role helper](../../scripts/capture-harbor-fleet-publisher-secret-id.py).
Unlike the existing bulk capture recipe, it never loops over readers, lists
SecretIDs, revokes existing IDs, updates a RoleID, or changes a role or policy.
The role is exactly `svc-homelab-iac-openbao-harbor-fleet-readers-publisher`.

The helper uses this owner's `secrets/sops/secrets.yaml`, not another checkout
or a runtime dotenv loader. It extracts only `vault_root_token` and
`homelab_iac.openbao_harbor_fleet_readers_publisher_role_id`. A TLS-verified GET
to the exact role's `/role-id` must match the stored literal before issuance.
No namespace is configured. Redirects are refused, and HTTP errors are closed
before generic failure handling to prevent credential-bearing resource warnings.
Unexpected command arguments are rejected before any secret read or API call;
an unsupported `--dry-run` must never silently issue a credential.

Exactly one POST to that role's `/secret-id`, with an empty JSON object, inherits
the existing role's lifetime and policy. There is no retry loop or TTL override.
Only `homelab_iac.openbao_harbor_fleet_readers_publisher_secret_id` is captured
through native `sops set --value-stdin`. Credentials stay in process memory and
stdin, never command arguments, environment additions, logs, or stdout.

Capture works on a mode-0600 encrypted temporary copy beside the store. The
exact new field is read back privately; the original encrypted bytes must still
match before atomic replacement. Native Sops may rewrite ciphertexts or metadata;
the logical change is only the named SecretID field. Other credentials are never
decrypted by this helper. Temporary encrypted copies are removed on exit. A
concurrent source edit is preserved and makes capture fail closed.

## Evidence and limits

The [stubbed command contract](../../tests/harbor-publisher-bootstrap/test_capture.py)
invokes the real Just entrypoint and helper in an isolated fixture checkout. All
Sops commands and HTTP requests are intercepted; tests cannot consult the real
store or live service. The positive pipeline failed before implementation:
`AssertionError: 1 != 0 : Controller-only capture must complete without bulk reader rotation`.

Six tests cover the successful single-field transaction, exact role mismatch,
forbidden/empty lookup, redirect rejection, unsupported Sops, whitespace refusal,
issuance/capture failures, empty issuance response, concurrent edits, and argument
rejection. Initial
GREEN found a credential-bearing `ResourceWarning` from an unclosed HTTP error;
closing it repaired the root cause. The first suite passed 5/5; a second
assertion-failing RED exposed ignored arguments, then the guarded suite passed
6/6. Adjacent Harbor contracts passed 45/45. Owner lint, formatting, and doc-link
checks passed. Hosted CI now runs
the same contract. These are stubbed source checks, not live capture evidence.

Local Sops help confirms `set --value-stdin`; no compatibility fallback is added.
Run `python3 -m unittest discover -s tests/harbor-publisher-bootstrap -v`.
Independent review and hosted CI remain delivery gates owned by the parent.

## Waiting work, risks, and recovery

After reviewed source merges, execute the single-purpose recipe once from that
merged owner's checkout, with the existing owner Sops key selection. Then verify
controller authentication through the approved owner preflight before resuming
the separate two-unit IaC plan review. No deployment, consumer restart, publisher
lookup, image publication, model promotion, or device call belongs to this recipe.

If any failure occurs after the issuance request starts, issuance may have
succeeded even if capture did not. The helper stops with “do not rerun”; do not
generate another SecretID, revoke IDs, or bypass the provider with a root token.
Preserve the original Sops store and seek scoped operator reconciliation. No
credential cleanup mutation is implicit. Source rollback removes this entrypoint
only; it cannot undo an issued credential. Reader/Cognee values and IaC state
remain outside the transaction.
