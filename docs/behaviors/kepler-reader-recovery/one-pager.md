# Kepler credential dependency recovery

**Status:** Source fix and independent review passed; publication and deployment pending.

## Outcome and why

The user's instruction was “do fixes” after the 2026-11-21 Kepler outage.
The coordinator observed a reboot followed by all six microVM start jobs failing
because the Harbor credential reader could not authenticate. That credential
incident is handled separately. This source change repairs a second failure:
recovering the reader does not, by itself, retry dependency-failed guest starts.
The active `microvms.target` and listening host proxy ports are not evidence that
its guest processes or the cluster API are healthy.

The existing configuration correctly makes every guest require the reader and
wait until its readiness check completes. `Restart=on-failure` retries the reader,
but the failed guest start jobs have already finished. A local systemd 262
experiment reproduced an active recovered reader with a guest still inactive.
The coordinator's deployed unit receipt confirms the same Requires/After edge;
no remote service was changed during this investigation.

## Change and boundary

Kepler's reader now also Wants the existing six guest units. Each reader start
transaction pulls them in; the existing ordering still prevents guest execution
until the reader's credential-file readiness check succeeds. A failed readiness
check continues to block the guests. Healthy-reader operation does not
continuously force guests active: an explicit guest stop remains effective.
A later reader restart can start those configured autostart guests again.

This is a Kepler-only relationship. The shared reader, Docker consumers,
authentication, file permissions, runtime credentials and registry policy remain
unchanged. There is no cached-credential fallback or new identity. The change
cannot repair an expired or revoked SecretID; the owning credential recovery
must succeed first. Guest failures unrelated to the reader are not automatically
retried by this relationship. Reader start-rate limits and permanent credentials
failures still require their normal operator recovery.

## Evidence and limits

The source-evaluated Nix assertion failed because guest units were absent from
`reader.wants`, then passed after the relationship was added. The first fixture
incorrectly assumed the effective autostart list had no duplicates; that harness
assumption was corrected before recording the behavioral RED. The final fixture
checks six unique guests, the retained Requires/Before boundary, reader restart
policy and restart-on-configuration-change protection. CI runs that evaluation.

The disposable local user-systemd test reads the actual evaluated reader Wants
list, then reproduces its dependency topology with uniquely named harmless
services. Before the fix it failed with “guest did not recover after the reader
became ready”; afterward it proved readiness failure blocks startup, recovery
starts the guest, and a subsequent explicit guest stop remains stopped. All
fixture units are removed in `finally`. This test requires a local user bus and
is not silently equated with a deployed VM test.

Run `nix eval --offline --impure --raw --file tests/kepler-reader-recovery/evaluate.nix`
and `python3 tests/kepler-reader-recovery/systemd-smoke.py` from this checkout.
RED receipts are `/tmp/kepler-reader-recovery-red.log` and
`/tmp/kepler-reader-systemd-red.log`; temporary logs are session evidence, not
repository artifacts. No guest image, private credential or production API was
used by these tests.

## Continuing work and recovery

Independent review reproduced both GREEN commands and found no material issue.
Owner lint, formatting, docs and diff checks passed. The offline Kepler toplevel
dry-run also exited zero; no candidate was built or activated. Live authentication repair, host activation and verification
of six running guests plus the real Kubernetes API remain the coordinator's
separate work. Removing the added Wants relationship restores the old source
behavior without changing credential material; it also restores the requirement
to explicitly retry guest starts after reader recovery. Do not restart or stop
the production reader as a test: its existing required-by relationship can stop
running guests.
