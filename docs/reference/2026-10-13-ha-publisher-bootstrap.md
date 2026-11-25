# Harbor publisher bootstrap: controller-only capture

**Status:** Native Sops source repair independently reviewed on 2026-10-18;
publication, hosted CI, and merge pending. The earlier merged-helper
invocation exited 1 with the encrypted store unchanged; its operational phase
remains unresolved. This source-only follow-up performs no live credential operation.

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

`just --no-dotenv capture-harbor-fleet-publisher-secret-id --exclusive-secret-store` calls the
[fixed-role helper](../../scripts/capture-harbor-fleet-publisher-secret-id.py).
Unlike the existing bulk capture recipe, it never loops over readers, lists
SecretIDs, revokes existing IDs, updates a RoleID, or changes a role or policy.
The role is exactly `svc-homelab-iac-openbao-harbor-fleet-readers-publisher`.

The helper uses this owner's `secrets/sops/secrets.yaml`, not another checkout
or a runtime dotenv loader. Before issuance it inspects the exact existing
SecretID field's ciphertext through `yaml.safe_load` and requires Sops'
`ENC[AES256_GCM,...,type:str]` wrapper as the **owner-declared type**. It then
extracts only that exact field as a raw literal, refusing missing fields,
objects, lists, nulls, owner-declared numeric/boolean types, empty strings, and
surrounding whitespace or newlines. Sops scalar
extraction returns unquoted strings even with `--output-type json`; parsing
that output as JSON is incorrect and cannot preserve scalar types. No parent
mapping or complete store is decrypted into the helper. Its only other
extractions are `vault_root_token` and
`homelab_iac.openbao_harbor_fleet_readers_publisher_role_id`. A TLS-verified GET
to the exact role's `/role-id` must match the stored literal before issuance.
No namespace is configured. An explicit empty `ProxyHandler` disables inherited
HTTP proxy settings. Redirects are refused, and HTTP errors are closed
before generic failure handling to prevent credential-bearing resource warnings.
Missing `--exclusive-secret-store` or unexpected arguments are rejected before
any secret read or API call; an unsupported `--dry-run` must never silently issue
a credential. The acknowledgement is not permission: it asserts an already
approved exclusive window and cannot establish one itself.

Exactly one POST to that role's `/secret-id`, with an empty JSON object, inherits
the existing role's lifetime and policy. There is no retry loop or TTL override.
Only `homelab_iac.openbao_harbor_fleet_readers_publisher_secret_id` is captured
through native `sops set --value-stdin`. Credentials stay in process memory and
stdin, never command arguments, environment additions, logs, or stdout.

Capture holds a nonblocking exclusive `flock` on the stable mode-0600
`secrets/sops/.secrets.yaml.harbor-publisher.lock` from before the encrypted
snapshot through issuance, verification, and replacement. Contention stops
before any Sops read or API call. The ignored lock file remains after release;
never unlink or replace it, since another inode would split the lock protocol.
Capture works on a mode-0600 encrypted temporary copy beside the store. The
exact new field is read back privately; the original encrypted bytes must still
match before atomic replacement. Native Sops may rewrite ciphertexts or metadata;
the logical change is only the named SecretID field. Other credential values are
never returned to this helper. Temporary encrypted copies are removed on exit.

**Strict operational precondition:** obtain explicit approval for a single-writer
maintenance window before executing the recipe. Use only the trusted, reviewed
owner repository's encrypted store, never an untrusted file. Before execution,
the runner/operator must verify clean source at the reviewed merged revision and
compare the encrypted store bytes with the reviewed pre-run baseline. These are
operator preconditions, not new helper-enforced provenance checks. The helper's
fixed store path and later byte comparison do not authenticate its input.
Every writer/editor of this
store must acquire that same exclusive lock before reading and hold it through
its final replacement, or remain stopped for the entire window. The existing
bulk capture and ordinary Sops editors do not automatically honor this lock;
do not run them concurrently. The byte comparison still detects earlier
noncooperating drift, but cannot protect the comparison-to-replace window from
nonparticipating editors. Advisory locking does not make that guarantee.

**Type metadata trust limit:** Sops MAC does not authenticate the scalar type
marker. Deliberately changing only `type:int` to `type:str` can change the
interpreted type without a MAC failure; this guard does not detect such
tampering. It validates the owner-declared type under the trusted-store
precondition, not the cryptographically authenticated original type. Independent
review disproved the main review prompt's contrary MAC assumption; that
assumption was not part of the human seed. Authenticated type provenance would
require reopening accepted behavior and a format/provenance change, outside
this repair. Parent must disclose this trust assumption before seeking any new
capture authorization.

## Evidence and limits

The [stubbed command contract](../../tests/harbor-publisher-bootstrap/test_capture.py)
invokes the real Just entrypoint and helper in an isolated fixture checkout. All
Sops commands and HTTP requests are intercepted; tests cannot consult the real
store or live service. The positive pipeline failed before implementation:
`AssertionError: 1 != 0 : Controller-only capture must complete without bulk reader rotation`.

The original six tests covered the successful single-field transaction, exact role mismatch,
forbidden/empty lookup, redirect rejection, unsupported Sops, whitespace refusal,
issuance/capture failures, empty issuance response, concurrent edits, and argument
rejection. Initial
GREEN found a credential-bearing `ResourceWarning` from an unclosed HTTP error;
closing it repaired the root cause. The first suite passed 5/5; a second
assertion-failing RED exposed ignored arguments, then the guarded suite passed
6/6. The 2026-10-18 refresh preserved that first draft at `b3ce206c`, then rebased
cleanly onto `264f8b66` (rebased HEAD `480bb350`). New assertion-failing regressions
proved all three reviewed P2 findings and the missing acknowledgement gate before
their fixes. The expanded suite passes 11/11 with 25 fixture pipelines. Its real
stdlib opener is built under synthetic proxy settings; only network execution is
intercepted. Kernel `flock` contention is exercised at preflight and inside the
final comparison-to-replacement window. The latter covers cooperating writers,
not editors ignoring the protocol. Refreshed adjacent Harbor contracts pass
45/45, with six pre-existing loopback-server ResourceWarnings. Owner lint,
fmt-check, docs-check, and scoped Ruff pass; refresh receipts belong to the
parent source handoff. Hosted CI is configured
to run this contract but has not run for this refreshed candidate. These are
stubbed source checks, not live capture evidence.

Local Sops help confirms `set --value-stdin`; no compatibility fallback is added.
Run `nix develop -c python -m unittest discover -s tests/harbor-publisher-bootstrap -v`.
The owner devshell explicitly provides Python/PyYAML, Sops, and age, so the
existing CI contract step runs both stubbed and native regressions. PyYAML
parses encrypted YAML rather than inventing a partial YAML parser at this type
boundary; the stdlib has no YAML parser. Missing native tools fail the gate,
never silently skip it.

The native regression uses a freshly generated temporary age identity and dummy
store in an isolated fixture checkout, with all HTTP execution intercepted. Its
valid string failed before the source fix: `Native valid string target must pass
before fake POST and complete capture`, with zero GET/POST requests and one
target extraction. Native extraction was independently asserted to return the
unquoted dummy string. The repaired suite passes 12/12: the original 11 tests
retain acknowledgement, lock, proxy, one-POST, and failure coverage; the native
test covers eleven fixtures. The native positive case runs real Sops
encryption, exact extraction, stdin set, and readback, makes exactly one fake
POST, and preserves every other logical dummy field. Nine invalid/missing
target cases make zero HTTP requests and leave encrypted bytes unchanged.
A deliberate numeric-to-string marker mutation is the eleventh fixture: native
Sops interprets it as string `"7"` without MAC failure, and the helper completes
one fake GET/POST and native stdin set. This is an executable limitation of
owner-declared typing, not a security success against an untrusted store. The
unchanged declared numeric/boolean fixtures still stop before any HTTP.
No real store, identity, service, or credential is consulted by these checks.

Historical review of the earlier source:
Fresh independent review verified the three P2 closures and acknowledgement
gate with no remaining findings, reran all 11 tests/25 fixture pipelines and
owner source checks, and marked the candidate source-ready. Hosted CI, merged
source and explicit exclusive-window approval remained separate gates. That
earlier suite did not test native Sops encryption; its scalar mock incorrectly
returned JSON-quoted strings. The follow-up corrects that mock to model native
raw output and typed encrypted wrappers.

## Waiting work, risks, and recovery

Fresh independent final review accepted the explicit trusted-owner boundary,
reran 12/12 tests with eleven native fixtures, and found no remaining source
blocker. The type-mutation experiment and lack of authenticated-type protection
remain documented, not erased. Parent owns hosted CI, publication and merge;
those do not resolve the earlier capture or authorize another attempt. The earlier
failed invocation remains stopped before plan/login; these fixture results do
not resolve its operational phase or authorize another capture. Parent must
reconcile that attempt and obtain any applicable execution approval before
another real operation. No deployment, consumer restart, publisher
lookup, image publication, model promotion, or device call belongs to this recipe.

If any failure occurs after the issuance request starts, issuance may have
succeeded even if capture did not. The helper stops with “do not rerun”; do not
generate another SecretID, revoke IDs, or bypass the provider with a root token.
Preserve the original Sops store and seek scoped operator reconciliation. No
credential cleanup mutation is implicit. Source rollback removes this entrypoint
only; it cannot undo an issued credential. Reader/Cognee values and IaC state
remain outside the transaction.
