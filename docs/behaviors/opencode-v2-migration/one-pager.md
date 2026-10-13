# OpenCode V2 backends: delivery status

**Status:** revised candidate locally GREEN; live-generation review and activation pending.
**Stage / revision:** RV second draft / 3, 2026-10-13.

## Outcome and basis

The candidate restores two explicitly addressed native V2 backends and ol/ow
clients on Endeavour. New databases, cache and state are separate from V1.
Original history/schema remain untouched; only the approved homelab V1
permission change to 0600 is planned. Optional plugins remain off.

The verbatim human seed, accepted scenarios and reconciled checks live in
the owning [leaf migration record](https://github.com/ErikBPF/opencode-flake/tree/5dca70f302d8b8ad5f52feea2c2bac347cd24858/docs/behaviors/opencode-v2-migration).
[Leaf PR #55](https://github.com/ErikBPF/opencode-flake/pull/55) passed security,
full checks and both package builds; it merged with Q-6 authorization.
Main CI published and verified FlakeHub 0.1.54 at the matching revision.
Only that input changed in the consumer lock; exact consumer 2.0.27 builds.

## Decisions and delivered boundaries

Q-1 selects native backends, not the V1 Rust client. Q-2 keeps Fold/sidebar
opt-in. Q-3 authorizes Endeavour activation after GREEN. Q-4 authorizes green
commits/pushes/PRs, not Desktop merge. Q-5 permits legacy chmod only. Q-6
authorizes leaf merge/publication/pin. Q-7 restores the current pinned
Ponytail V2 adapter 0.1.0 after upstream 5.1.1 failed native checks; its
update is explicitly deferred, not silently declared compatible.

Home and work server defaults, including title model, use their own gateway.
Only the selected scoped sops key is sourced. Servers bind loopback with
private persistent passwords, UMask 0077 and explicit suppression of legacy
Claude discovery. Native clients select exact packaged binaries/endpoints.
Keep-old tmux/Herdr behavior and pending PATH fix are preserved. Independent
trial MCP work is not replaced by normal-user activation.

Global cli.json manages prompt permissions, native tabs and equivalent
terminal preferences. Native 2.0.27 `tool.use` policies override agent secret
read allowances; shell commands outside exact inspection rules ask.
Compaction uses keep.tokens; self-update is disabled. Donsetch is pinned
4.7.4, Nix MCP inherits the packaged executable, redundant filesystem MCP
and broad project shell overrides are removed. Duplicate startup prose was
trimmed without deleting safety constraints.

## Evidence, failures and reconciliation

RED assertions preceded backend/configuration changes, updater coverage,
recipe quoting, compound-command restrictions, version-specific policy,
systemd discovery flag and title routing. Leaf review's shell-injection
finding was fixed and verified. Consumer review found policy rename and
premature plugin readiness; both are corrected. Required plugins and probe
must register before permission tests can claim success.

Five settings and five project checks pass. Backend/workspace checks cover
isolation, forwarding, routing, chmod fixtures and lifecycle preservation.
Exact 2.0.27 native auth/PID/client/401 smoke, real RTK model → shell → model
continuation, header/Ponytail injection and three native plugin/permission
checks pass. Node checks cover provider filters and adapter transforms.

Upstream Ponytail failed after three bounded hypotheses. The explicit
entrypoint experiment was reverted; accepted Q-7 compatibility fallback then
passed unchanged native injection assertions. Optional runtime trials were
cancelled; no quota, saving or compatibility claim is made for them. Static
settings are not UI/key-delivery evidence. Gherkin has no executable step
bindings; these receipts do not imply whole-scenario completion.

Final rerun passed 28 backend/workspace, 10 profile and five project checks,
exact-version auth smoke and Node adapter checks. An initial profile rerun
accidentally used PATH's older 2.0.21 and failed the 2.0.27 policy checks;
the corrected exact-binary command passed without code or assertion changes.
Owner lint/fmt/docs and Endeavour/Orion/Apollo/Pathfinder dry gates all pass
against the published pin. No full-system activation or local flake check ran.
The native permission fixture also passes with the backend's inline
provider-policy layer, proving that it retains global secret-read denials.

## Continuing work and recovery

Review candidate-versus-live user-generation drift before
the documented normal-XDG home-switch. No other host activation is approved.
Verify both live PIDs/versions, authentication, provider/tool/MCP behavior,
V1 metadata and surviving desktop sessions afterward.

Both old V1 unit closures and previous HM generation have retained GC roots
in the ignored task receipt directory. Original V1 DBs are still present;
last pre-activation health was 1.18.31 and metadata unchanged. Recovery uses
matching retained source/generation, not an unrooted binary or history import.
The [session guide](../../guides/opencode-v2-sessions.md) records shortcuts,
privacy limits and disabled experiment fragments.
