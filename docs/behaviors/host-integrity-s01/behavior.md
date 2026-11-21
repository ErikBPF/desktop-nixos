# S01: persistent host integrity reporting

## Human seed

> invoke agent to do slices 0 to 3

## Accepted scope

Implement S01 from Homelab's `docs/plans/host-integrity/slices/S01-reporting.md`
packet and frozen `docs/plans/host-integrity/interface.md`, revision 1,
2026-11-20. The coordination checkout is
`/home/erik/Documents/erik/homelab/worktrees/host-scan-one-pager`.

Configured checks emit never-run state before their first attempt. Starting an
attempt does not clear prior complete coverage or findings. Failed and partial
attempts retain those values. A clean rerun cannot clear findings automatically.
Publication uses a private persistent record and a separate root-owned readable
textfile directory. Partial writes cannot replace a complete metric file.

Legacy writable textfiles retain existing backup metrics but cannot inject the
reserved `host_integrity_*` namespace. The trusted collector overwrites instance
with its configured hostname and retains only instance/check plus transport job.
No host is enabled in S01. No deployment, scan or production telemetry proof is
claimed. S02 owns actual tool execution and resource/receipt policy.
