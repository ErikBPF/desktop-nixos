# Persistent OpenCode backends: deployment receipt

**Stage / revision:** GREEN / E2E / 2
**Status:** Deployed and runtime-verified; original profile test blocked
**Owner / date:** desktop-nixos / 2026-09-15T17:00:46Z
**Basis:** User authorized "Configure and deploy", including existing pending Home Manager changes. Requested two persistent loopback backends, existing profile wrappers, no launcher edits, no process kills, and no commit or push.

## Outcome and why it matters

Endeavour now has enabled user services for homelab and dataplatform, independent of attached terminals. Both report healthy OpenCode 1.18.30 and resolve their requested repository directory through the read-only API.

## What changed

[workspace-sessions.nix](../../../modules/desktop/workspace-sessions.nix) reuses its existing project list and installed profile packages. Each service uses an absolute wrapper path, the existing service PATH pattern, `Restart=on-failure`, `RestartSec=2`, and `default.target`. The module is composed only by Endeavour. Existing user linger is enabled.

Follow-up seed: "create default ol and ow comands for each". Accepted mapping:
`ol` invokes `opencode-home attach http://127.0.0.1:4096 --dir /home/erik/Documents/erik/homelab`;
`ow` invokes `opencode-work attach http://127.0.0.1:4097 --dir /home/erik/Documents/nstech/dataplatform`.
Two `writeShellApplication` packages in the same module execute absolute existing
Home Manager profile binaries and forward `"$@"`. Deployment of the dirty checkout
was authorized for this extension.

## Evidence and limits

| Check | Result |
|---|---|
| `just lint && just fmt-check` | Pass after formatting only the edited module. |
| `python3 tests/opencode-profiles/test_profiles.py` | Fails before assertions: `file '/home/erik/Documents/erik/desktop-nixos/detached' has an unsupported type`. |
| Same profile test, temporary in-memory Git-backed flake URL substitution | 1 test passes; test source and existing filesystem object untouched. This does not make the original command green. |
| `just dry endeavour` | Pass; 49 derivations planned. |
| `just home-switch endeavour` | Pass; 10 derivations built, Home Manager activated. |
| `systemctl --user show` | Both enabled/active/running, zero restarts, expected wrapper ExecStart and cwd. |
| `ss -ltnp` | Only `127.0.0.1:4096` (homelab PID 2914861) and `127.0.0.1:4097` (dataplatform PID 2914857). |
| `/proc/<pid>/cwd`, `/proc/<pid>/exe` | Correct repositories; both execute packaged OpenCode 1.18.30. |
| GET `/global/health` | Both HTTP 200, `healthy=true`, version 1.18.30. |
| GET `/path?directory=<absolute-repository>` | Both HTTP 200; directory and worktree match requested repository. |

Existing tmux backend retains PID 4745. Home Manager also stopped/started desktop-window units while activating authorized pending changes; survival of every pre-existing GUI process is not established. No manual kill or model request was issued. Reboot and forced-failure recovery were not exercised.

### Shortcut extension verification

- No `ol`/`ow` names found in module source or interactive zsh command lookup before installation.
- `just lint`, `just fmt-check`, and `just dry endeavour` passed; dry-build planned 49 derivations, including both wrappers.
- First `just home-switch endeavour` built 10 derivations and installed wrappers, but activation failed in the existing `installCodexPonytail` hook: `Could not resolve host: github.com`. After `getent ahostsv4 github.com` resolved, one retry passed.
- Activation reported degraded `desktop-window-homelab-agent-6.service`; its cause was not investigated in this shortcut change.
- Installed `/home/erik/.nix-profile/bin/ol` and `/home/erik/.nix-profile/bin/ow` resolve in interactive zsh. Store wrapper contents match both accepted mappings and preserve `"$@"`; `ol --help` and `ow --help` pass. No interactive TUI or model request was opened.
- Both backend health endpoints remain healthy on 1.18.30. PIDs remain 2914861 and 2914857, active with zero restarts after activation.
- Staged diff and unrelated tracked diff SHA-256 values match the starting baseline. Prior backend declarations and documentation remain intact. `git diff --check` and `just docs-check` passed after this receipt update.

## Decisions and corrections

Use existing wrappers rather than duplicating credential/profile logic. Preserve the unrelated `detached` object; use Git-backed evaluation only as diagnostic evidence. Original staged and unrelated unstaged diff SHA-256 values stayed unchanged through deployment. No human decision required for completed authorized deployment.

## What continues / what waits

Attach explicitly to each repository:

```sh
ol # homelab, home backend
ow # dataplatform, work backend
```

## 2026-09-21 database isolation and compaction

Both services now set an explicit `OPENCODE_DB`: `opencode-homelab.db` for
port 4096 and `opencode-dataplatform.db` for port 4097. Historical records were
split by project worktree; `/home/erik/Documents/nstech/dataplatform*` belongs
to dataplatform and every other project belongs to homelab. Each event stream
retains its latest event per session and event type.

The stopped source database was backed up and integrity-checked before the
split. Both resulting databases pass SQLite integrity and foreign-key checks;
they are 240 MiB and 186 MiB respectively. Runtime verification observed both
services healthy on their expected ports and explicit database paths, with
idle CPU below 1% per server. The retired source remains recoverable under the
local OpenCode backup directory.

## Risks and recovery

Original profile-test filesystem blocker remains separate work. Rollback requires removing only the new backend declarations and running `just home-switch endeavour`; obtain authorization before retiring live backend sessions. No commit or push made.
To remove only the shortcuts, remove the two wrapper packages and run the same
Home Manager recipe; keep backend declarations intact.
