# OpenCode V2 backends: delivery status

**Status:** Endeavour activated; live checks pass; CI fixture repair and historical GitGuardian review pending.
**Stage / revision:** RV second draft / E2E / 10, 2026-10-13.

## Outcome and basis

Endeavour now has two authenticated native V2 2.0.27 backends and explicit
ol/ow clients. Databases/data/state/cache are isolated from V1. History import
is separate; original V1 inode/size/mtime remain unchanged. Only approved
homelab chmod changed; both V1 files now have mode 0600.

The verbatim seed and accepted contract remain in the
[owning leaf record](https://github.com/ErikBPF/opencode-flake/tree/5dca70f302d8b8ad5f52feea2c2bac347cd24858/docs/behaviors/opencode-v2-migration).
[Leaf #55](https://github.com/ErikBPF/opencode-flake/pull/55) passed required
CI, merged with Q-6 authorization and published FlakeHub 0.1.54 at matching
revision. Only that consumer input changed. [Desktop #373](https://github.com/ErikBPF/desktop-nixos/pull/373)
is open; initial candidate commit is `1cff636`. No Desktop merge or other
host activation is authorized or performed.

## Decisions and boundaries

Q-1 selects native V2, not Rust/V1 pairing. Q-2 leaves Fold/sidebar off.
Q-3 authorizes Endeavour activation after local GREEN. Q-4 permits green
commits/pushes/PRs. Q-5 allows legacy chmod only. Q-6 permits leaf
merge/publication/pin. Q-7 retains pinned Ponytail V2 adapter 0.1.0 after
upstream 5.1.1 failed; that update is explicitly deferred.

Loopback servers use private persistent passwords, UMask 0077, scoped sops
keys, home/work gateway and title defaults, and explicit legacy-Claude
discovery suppression. Native clients select exact binaries/endpoints.
Keep-old desktop sessions/PATH fix and isolated controlling trial survive.
Global CLI owns prompted permissions/tabs. Supported compaction uses
keep.tokens; self-update is disabled. Native `tool.use` policies protect
secret reads despite overrides. RTK rewrites after original-command approval.
Donsetch is pinned 4.7.4; packaged Nix MCP replaces unpinned project override.

## Evidence and repairs

RED preceded backend isolation, updater/recipe safety, compound-command
restrictions, policy rename, discovery flag and title routing. Independent
reviews verified and reconciled those findings. Native readiness requires
plugins plus probe agent; missing registration cannot falsely prove denial.
Upstream Ponytail exhausted three hypotheses; approved adapter fallback
passed unchanged injection assertions. Discovery receipts/first-draft hashes
are retained outside Git, with no backdated RED or weakened acceptance.

Final local gates passed 28 workspace/backend, 10 profile and five project
checks; exact native auth/PID/client/401 smoke, synthetic RTK model/tool
continuation, header/injection and Node checks passed. Inline backend
provider policies retain global secret denials. Owner lint/fmt/docs and
four touched-host dry gates passed. Accidental PATH 2.0.21 test failure was
corrected by selecting exact 2.0.27, without assertion changes.

Normal-XDG home-switch completed after independent live-generation drift
review. Both live API/native clients match owning 2.0.27 unit PIDs and reject
unauthenticated requests. Secret denials survive session overrides; new
DB/password modes are 0600. All eight original windows and 16 tmux panes/PIDs
survived; desktop-tmux remains PID `161737`. Both MCPs connected on both
backends. Home completed real model → approved pwd once → model continuation.

Work rejected `reasoning_effort`. Actual managed-model request regression
failed, then passed after removing only Work DeepSeek effort options/variants.
First repair activation exposed cached old server config despite updated
managed file. A config-hash restart-trigger regression observed RED/GREEN;
final normal-XDG redeploy restarted both backends. Work now completes real
model → approved exact pwd once → model continuation. Refreshed identity,
auth, secret-denial, V1 metadata and window/pane checks pass. Home options
unchanged.

Initial CI passed six host evaluations, repository secrets, lock and k3s.
Lint/format passed; native tests failed missing scratch parent/unrealized
Ponytail. Fixtures now create parents; CI realizes Ponytail/RTK, exposes RTK
on PATH and selects exact binary. Fresh-HOME tests and revised workflow
OpenCode step pass locally. GitGuardian flagged temporary auth-file mode
fixture; path variable clarified, no exclusion/dismissal. Refreshed CI still
passed ten checks but exposed the wrapper stub's PATH-dependent Python
shebang on Ubuntu. The fixture now uses absolute sys.executable; service
PATH and assertions stay unchanged. All 28 workspace tests and owner
lint/fmt/docs pass again; both wrapper checks also pass with an unavailable
service PATH, proving interpreter portability. This is runner setup failure, not
backend behavioral RED. GitGuardian still scans historical commit `1cff636`
and occurrence `303907955` (incident `38171296`): reported line checks
generated auth-file mode, not a literal credential. Manual false-positive
review remains required; no history rewrite or security bypass is applied.

## Limits and recovery

Both backends' configured Donsetch returned Example Domain's heading and paragraph;
configured Nix returned programs.bash.enable's boolean type/default true
through a completed execute call and model continuation. Native read/shell
were denied. Whole-MCP-tool/execute permissions are not argument or network
isolation. Actual terminal key delivery and optional runtime trials remain
unverified. Services are active with zero automatic restarts; owning/native
client PIDs are home `1460762` and Work `1460761`. No extra host activated.
No token-saving/quota claim or bound Gherkin completion is asserted.
Old V1 unit closures and prior HM generation have retained GC roots;
recovery uses matching source/generation, never history import. Passwords
and provider keys stay out of receipts/chat. The
[session guide](../../guides/opencode-v2-sessions.md) records shortcuts,
disabled fragments and privacy limits.
