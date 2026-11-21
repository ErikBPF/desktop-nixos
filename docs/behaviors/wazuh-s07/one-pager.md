# S07: isolated host-view FIM preparation

**Status:** Disposable local proof passed; production FIM remains disabled. Retention is accepted; backup destination, restore evidence and deployed S06 proof remain open.

## Outcome and why

The existing Orion agent runs in a container. Enabling a default `/etc` rule
would watch the container filesystem and could falsely imply host coverage.
This preparation proves the smallest alternative: an explicit read-only host
directory containing one harmless configuration-shaped fixture. Actual pinned
Wazuh 4.14.7 observes host mutation and restoration without file contents or an
unwatched control appearing in its native event stream.

This began on S06 Desktop `65354915` in `worktrees/wazuh-fim-s07`.
After S06 merged, publication was rebased onto main `3f0e7841` and retargeted to
main. All fifteen fixtures and owner lint, formatting and documentation checks
passed again; production FIM remains disabled.
It changes only disposable tests, their fixture, the approved existing CI step
and documentation. No production module, host import, enrollment key, manager
rule, index policy or standing credential changes. Orion's deployed trust,
identity and fresh SSH recovery must be verified before a real FIM pilot.

## What the fixture does

The test creates a temporary host `watched` directory and separate unmounted
`control` directory. A fresh container receives only the watched directory at
`/host-fim:ro`, a private test event socket and the fixture configuration. Its
network is disabled; the manager and standing agent are never contacted.
The actual `wazuh-syscheckd` watches `/host-fim` in realtime with recursion zero,
file limit eight, maximum ten events per second and `report_changes="no"`.
Rootcheck is disabled. Manager synchronization is disabled only in this isolated
queue fixture because no manager exists; production must settle synchronization
and recovery explicitly rather than copying this test configuration blindly.

The test waits for the initial scan, changes the watched file once, writes the
outside control, then restores the original file. It requires two modified
events, the restored SHA-256, no content/diff payload, no control path and no
rootcheck event. A bounded quiet interval catches queued duplicates; total
records are capped. An attempted container write must fail. Temporary identity,
filesystem and process state are removed; production identity is not mounted.

## Evidence and limitations

A disabled FIM fixture first failed the real missing-event assertion; the source
file existed and the daemon ran. After enabling the bounded rule, a harness
failure exposed NUL-terminated queue records. Pinned source inspection also
showed `-c` only redirected FIM configuration while rootcheck read the default
file. The corrected harness mounts its configuration at the actual default path
and checks that rootcheck emits nothing. The earlier rootcheck ran only inside
a disposable container with no broad host filesystem mount.

Independent review tightened both mutation/restoration SHA checks and required
absence of a diff field on both events. Final combined validation passed 15 tests: existing source contracts, real TLS
trust fixtures and this actual syscheck fixture. This is local host-view/event
production proof, not manager indexing, attribution, Discord delivery, seven-day
capacity or backup restore evidence. No claims are made about broad NixOS `/etc`
coverage: symlink replacement and file bind mounts need separate treatment.

## Next decision, activation and recovery

The user answered “do as recomendation”: 30-day alert retention, daily encrypted
index snapshots, manager-state backup and isolated restore are accepted. The
approved backup destination is still being grounded by the coordinator; do not
provision a new store or infer credentials. No Wazuh restore recipe was found.
Build and exercise an isolated restore before claiming recovery.

After those gates, prepare only Orion's root-owned
`/var/lib/wazuh-fim-canary/watched/sshd_config.fixture` and its outside control,
a source-owned read-only bind and a bounded rule. Verify real host mutation,
restoration, retained agent identity, indexed notification and heartbeat recovery.
Keep the existing SSH collector. Revert the rule/bind if acceptance fails;
never delete enrollment state or accept a new baseline automatically. Workstation
expansion and seven-day observation remain separate gates.

Exact execution and decision metadata: [test receipt](test-contract.md).
