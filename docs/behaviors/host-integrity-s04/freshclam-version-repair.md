# S04 Runtime tool invocation repairs

**Status:** Runtime failure reproduced; source repair passed focused checks; reviewed publication and runtime retry pending.

The first authorized Endeavour signature attempt failed before updating definitions.
Its private receipt reported state 4, one error and no complete/database timestamp.
The installed FreshClam 1.5.4 executable tried `/etc/clamav/freshclam.conf`, which
is absent. The configured job instead supplies an explicit immutable configuration.
The runner had dropped that argument while invoking the initial `--version` probe.
The real executable failed without the configuration and printed its version
successfully with the declared `--config-file` argument. No signature update or
complete coverage was claimed from the unsuccessful attempt.

The shared runner now retains the configured signature command's arguments for
its version probe. Store and AV version invocations are unchanged. The updater,
resource limits, private receipts, genuine-finding protections and mutable scope
are unchanged; no machine-global ClamAV configuration is introduced.

A regression fixture requires the declared configuration before it reports a
version. It failed with state 4 where complete state 2 was required, then passed
after the two-line repair. All 56 runner/reporter tests passed, as did lint,
format and whitespace checks. The first test invocation lacked pytest and was
an infrastructure failure, not RED; the actual RED used the owner's installed
pytest runner. Local receipts: `/tmp/host-integrity-version-red.log` and
`/tmp/host-integrity-version-green.log`.

This repairs the failed version boundary; it does not prove definition downloads
or freshness. Retry through the reviewed owner unit, inspect its structured
state and definition timestamp, then continue bounded store/Downloads checks.
Systemd's successful wrapper exit alone is not successful coverage. Preserve the
failed receipt and stop after three unsuccessful repairs of the same cause.
Rollback restores the prior source revision while retaining private evidence;
do not manufacture a complete timestamp or install a global configuration to
mask the missing argument.

## Store verification and durable findings

The first store attempt also failed coverage: the actual daemon-access preflight
passed, but the runner exhausted its unchanged 256 KiB output limit. Pinned Nix
2.35.6 emits routine per-path checking messages at its default verbosity. Store
verification now uses `--quiet`. An actual disposable local store containing a
harmless modified fixture confirms that quiet mode still reports corruption and
exits 1; it only removes routine checking messages. No live store path was changed.

A separate regression exposed a lost finding when a corruption diagnostic was
followed by output overflow. The runner now publishes each recognized corruption
finding before processing further output. A subsequent failure remains state 4
and retains its genuine-finding marker; neither failure nor a later synthetic
canary can silently clear it. Private receipts now retain a bounded exception
reason, allowing output-limit failures to be distinguished from other errors.
Paths and diagnostics remain private, outside metric labels.

The overflow regression failed with zero findings instead of one before the
repair. The Nix configuration assertion separately failed until `--quiet` was
added. All 58 runner/reporter tests and the stage configuration evaluation then
passed. Lint, formatting and documentation-link checks passed. Receipts:
`/tmp/host-integrity-store-repair-red.log`,
`/tmp/host-integrity-store-quiet-red.log`,
`/tmp/host-integrity-tool-repairs-green.log`, and
`/tmp/host-integrity-store-quiet-green.log`.

These are source and disposable-fixture results, not successful host coverage.
Keep the runtime input set frozen for the retry; the unrelated fleet input refresh
must not enter this bounded pilot activation. Preserve both original failed
receipts, inspect actual state after retry, and stop after three failed repairs
of the same cause. Resource and output caps remain unchanged.
