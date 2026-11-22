# Argus owner verification repair

**Status:** Source checks passed; runtime retry belongs to the credential handoff operator.

## Outcome and why

The Argus credential handoff encountered owner verification failures after the
container started. The deployment must distinguish a broken verification command
from a broken agent without bypassing credential convergence or health checks.
The human request remains “do fixes” and “merge and deploy”; this change repairs
the Desktop owner entry points used by that authorized work.

Read-only runtime evidence showed the three Hermes containers running, Argus's
healthcheck successful, and its timer waiting. The owner health recipe passed
Discord and HTTP checks, then failed because Argus's `python3` cannot import
PyYAML. Argus already ships `/opt/hermes/.venv/bin/python` with `ruamel.yaml`;
the declared Argus healthcheck uses that runtime. Daedalus's existing interpreter
and PyYAML check passed and remain unchanged.

The generic render verifier independently requires all Hermes render files to be
less than fifteen minutes old. Unchanged agent, Daedalus and wiki renders dated
November 10, although their permissions and owners were correct and Vault agent
was active. Their age does not establish whether an Argus-only update converged.

## Changes and owner route

`just hermes-agents-health`, including its use by `just start-hermes-argus`, now
runs Argus's model authorization check through its installed virtual environment
and safe ruamel loader. It still requires the configured default model to appear
in the authenticated model list. No package installation or host activation is
needed for this operator-side recipe change.

`just verify-hermes-argus-render` checks Vault agent and Argus are active, the
Argus environment render has mode `0400`, owner `root`, group `vault-consumers`,
and nonempty contents. It reads no credential values. The private handoff must
separately prove the expected value rendered before restart, then prove the
running process uses that value and the intended Grafana request succeeds.
Metadata verification alone is not credential convergence.

The retry uses the existing stop/start recipes followed by this scoped verifier;
it must not call the generic freshness verifier for an Argus-only change.
The generic all-Hermes verifier remains unchanged, including its known freshness
limitation. No second credential, runtime mutation, or retry is performed by this
source repair.

## Evidence and limits

`python3 -m unittest discover -s tests/hermes-healthchecks -v` first failed two
assertions: the executed model-check fragment raised `ModuleNotFoundError` for
Argus, and the old verifier rejected unchanged render timestamps. The corrected
recipes pass all three tests. Regression cases retain rejection of an
unauthorized model, wrong render metadata, empty render, and either unit being
inactive. Independent review caught systemctl's any-active behavior for multiple
unit arguments; a further failing mixed-state test preceded the per-unit fix.
Fixtures execute recipe shell and model-check Python with isolated Docker and
SSH substitutes; they do not prove live credential authorization.

The existing CI tooling contract already discovers this test directory. Runtime
handoff success remains a separate gate. Rollback is reverting the operator
recipes; it does not roll back Vault or Grafana credentials. The handoff owner
retains responsibility for credential rollback and container convergence.
