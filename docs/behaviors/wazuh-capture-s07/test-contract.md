# S07 Kepler capture contract

The user selected Wazuh activities and answered the recovery recommendation
“do as recomendation”. The coordinator authorized source preparation for the two
existing managers, with live quiesce, credential provisioning and daily activation
held until review and runtime prerequisites. The approved control mechanism is
exact named scale operations with independent recovery, not pod execution or a
custom maintenance endpoint.

## Observed checks

Run `pytest -q tests/wazuh-manager-capture` and
`nix eval --offline --impure --raw --file tests/wazuh-manager-capture/evaluate.nix`.
The explicit CI steps run the same focused suite and synthetic evaluation.

- Persist intent before scale-to-zero; restore both managers before archive
  export; snapshot and stop failures still recover; failed recovery retains
  intent; independent recovery acts only on outstanding intent.
- Require authoritative exact Argo replica delegation and the reviewed CSI
  server, share, subdirectory, PVC UID and PV claim binding.
- Attempt recovery of the second manager when the first API operation fails.
- Bound every API request by one wall-clock deadline that covers connect, headers
  and body. A trickling header or body must raise `TimeoutError` at that deadline,
  and a following scale request must still execute.
- Atomically replace private state with mode0600 and reject unowned snapshot
  cleanup names before invoking ZFS.
- Reject an old Pod UID, old/future timestamp, boolean timestamp, or failed
  graceful-shutdown marker.
- Nix defaults create no capture or credential service. Synthetic enablement has
  no capture schedule; boot/minutely recovery remains armed, with explicit
  resource limits and the dedicated runtime token path.

The orchestration seam was introduced as a callable no-op, then the five expected
behavior assertions failed (`/tmp/wazuh-capture-red.log`). Six additional policy
and binding assertions failed before their guards were implemented
(`/tmp/wazuh-capture-boundaries-red.log`). An initial discovery assumption used
legacy NFS PV fields; verified live metadata corrected it to the CSI attributes
before source freeze. The initial observations must not be presented as tests of
an unverified legacy-NFS production topology.

Later API, archive and Nix adapters were implemented before their regression
checks. This is a TDD deviation, not an additional RED claim. Twenty-one focused
checks and synthetic Nix evaluation passed; an independent reviewer reproduced
both with no material finding. Owner lint, formatting, structure, documentation
and offline Kepler toplevel dry evaluation passed. The normal owner dry command
was stopped after its known Orion cache fetch stalled; no deployment occurred.

## Remaining proof

These checks do not prove actual Kubernetes scale/termination timing, real ZFS
snapshot/export, Vault renewal, root service sandbox operation, Filebeat shutdown,
encrypted Restic readback, backup freshness, or isolated restore. The source remains
disabled. The native index artifact must validate before any manager quiesce;
the final assembler/encryption/cleanup acknowledgement integration is recorded below.

## Accepted integration continuation

After the Servarr leaf is reviewed and published, the Desktop consumer will pin
its exact commit and file SHA256. An operator authenticates the download and
materializes that exact script in a root-private revision directory; installation
verifies the hash after writing. The daily service has no GitHub credentials and
never executes the mutable Servarr checkout. Missing files, changed bytes, wrong
ownership, writable release files/directories, and unexpected revision strings
must fail before any manager scale operation.

One shared capture lock spans `select_index_capture()`, manager capture, and
`assemble(manager_dir, index_dir)`. A missing or stale native index artifact must
prevent quiesce. Assembly, encrypted backup, readback or cleanup-ack failure must
fail the service after manager recovery; none may publish a successful backup
claim. These failure cases received the observed RED/GREEN checks recorded below.

### Integration evidence

The accepted continuation produced six behavioral RED assertions for native
preflight, publication ordering/failure, exact hash execution and nonwritable
materialization (`/tmp/wazuh-capture-integration-red.log`). The installer produced
three assertion failures before implementation (`/tmp/wazuh-installer-red.log`),
and freshness produced two (`/tmp/wazuh-capture-freshness-red.log`). All thirty-two
focused tests now pass. Private-artifact loader tests use real files/descriptors
and modes while emulating root ownership; installer tests exercise real atomic
filesystem installation as the test user. Neither substitutes for the separately
gated privileged Kepler installation.

The final pin is Servarr `1c0dfb0d8e664be099485d48ed38a3ef5158da4d`, SHA256
`405be8c85afcf25553fb09a83ae96340a5913ff510b64d0fbb7dc11a901df4c4`.
The previous candidate was superseded by a public-fingerprint literal formatting
correction; runtime value and reviewed transport behavior are unchanged. The
published source has passed its full-history secret policy and owner tests.

## Recovery before rollback or disablement

Do not disable the module while a capture intent remains: removing its rescue
units would remove the automated recovery route. On the named Kepler host, stop
capture, run the existing recovery unit, and require successful recovery before
changing the configuration:

```sh
sudo systemctl stop wazuh-manager-capture.service
sudo systemctl start wazuh-manager-capture-recovery.service
sudo test ! -e /var/lib/wazuh-manager-capture/intent.json
```

Verify both named managers are ready through the approved Kubernetes owner route.
If credentials or the API are unavailable, stop rollback and use the operator
recovery route; do not delete the intent, enrollment state, private receipts or
unverified producer artifacts. The runbook commands are prepared instructions,
not a record of executed live recovery.


### Integrated review correction

The reviewer found that Kepler did not expose a bare `python3` in its system
profile. A new remote-command assertion and enabled-package Nix assertion failed
before correction (`/tmp/wazuh-installer-python-red.log` and
`/tmp/wazuh-installer-nix-red.log`). The enabled feature now declares Python and
the installer uses `/run/current-system/sw/bin/python3`; thirty-three tests and
the synthetic evaluation pass. This requires reviewed manual-only host bootstrap
before materialization; the recipe has not been executed live. The legacy
textfile's host-user-writable trust boundary remains an explicit alert-enrollment
gate pending coordinator direction.

### Final conformance review

The installer invokes the declared interpreter with `-I`, preventing the remote
operator directory or Python environment from shadowing standard-library imports.
The command assertion failed before this correction
(`/tmp/wazuh-installer-isolation-red.log`), then passed.

Final preflight review found that the authorized indexer PV was not inspected and
PV binding phase was not checked. Two behavioral assertions demonstrated those
gaps (`/tmp/wazuh-capture-pv-red.log`). The shared guard now requires exact claim
and CSI identity plus Bound phase for all three PVs before quiesce. Thirty-six
focused tests pass; a fresh reviewer independently reproduced seven affected
cases and found no material issue. This adds no Kubernetes authority. The source
was rebased onto `3f0e7841`, preserving existing CI selections. Runtime gates above
remain unmet; source review does not authorize activation.
