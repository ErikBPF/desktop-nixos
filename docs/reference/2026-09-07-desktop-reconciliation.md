# Desktop reconciliation and OpenCode rollout

**Status:** Endeavour and Orion activated; Orion and Apollo home/work real tool checks pass.
Pathfinder remains unverified since the rollout below. September 13 residual review
against `9b704841` retired the obsolete Gemini launcher and standalone journald
migration; Headroom remains deferred. Original audit against `1ed67c9` follows.

## September 13 residual closeout

The preserved draft stash is `6a98559779e9d2d13a2f7d20c404775e3965d26a`.
It was inspected without applying it; no runtime configuration changed.

- **Gemini launcher: retired.** The draft `herdr-repo` command targets `gemini`,
  contradicting the [accepted Orion/Apollo placement](https://github.com/ErikBPF/homelab/blob/main/docs/decisions/2026-09-07-orion-apollo-development.md).
  Current `modules/dev/herdr.nix` already supplies personal Orion `l1/l2` and
  work Apollo `w1/w2` entry points. Do not restore the draft or silently retarget
  personal repositories to Apollo.
- **Standalone journald API migration: retired against the current pin.**
  `nix eval --json --no-write-lock-file .#nixosConfigurations.discovery.options.services.journald --apply 'o: builtins.attrNames o'`
  succeeds and lists `extraConfig`, with no `settings` option. Discovery and
  Kepler already declare persistent 2G journals; the shared module retains its
  50M default. Keep those working declarations. Reconsider API migration only
  when a separately reviewed Nixpkgs update requires it, not as missing retention
  implementation.
- **Headroom: deferred.** The [Codex tooling record](codex-tooling.md) retains
  the adoption and reproducible-runtime questions. The intended benefit over
  the existing RTK path remains unspecified; retain the current endpoint.

The path inventory below is the September 7 historical audit, not a current
implementation queue. Subsequent reviewed publications delivered the independent
Codex tooling, manual fork-sync and display-capture work.

## Exhaustive stash review — September 13

The second pass inspected all ten Desktop stashes, not only the recent
preservation snapshot. Stashes remain intact; none was applied wholesale.

| Stash group | Current-source comparison | Disposition |
|---|---|---|
| `6a985597` | Recent publication snapshot; most paths already delivered. Retired Gemini/journald and deferred Headroom are covered above. The retained LUKS feature describes an operator scope already closed in Homelab. | Keep as historical recovery evidence; do not reopen the closed LUKS gate or replace current routing and package pins. |
| `a2727790`, `39908e17` | Repeated journald migration and older instruction/pin copies. | Superseded; retain supported declarations and current policy. |
| `a8aca81d` | Alloy NFS exclusion already present; SBX has newer upstream packaging and tests; Gemini aliases retired. | Already delivered or superseded; no older package/alias overlay. |
| `f216a075`, `4daeb7ea` | Ubuntu-work already includes the clipboard, keyboard and audio intent, with a newer private PulseAudio setup. | Retain the current implementation and its passing contracts. |
| `62bf51ae`, `ec569f06`, `49025c8f` | Existing system-key persistence precedes secret activation. Old login/host-key changes conflict with current policy; the key-rotation runbook still described the old single-store model. | Integrate the corrected [rotation procedure](key-rotation.md), not the stale authentication or bootstrap changes. |
| `b2ac927c` | NetBird server work predates retirement; Kepler parallel-control-plane assertions already exist in `tests/kepler-fast-state`. | Superseded or already covered. |

`ec569f06` also retains 252 generated Graphify files. Those caches are not
implementation source and remain excluded from publication.

RV verified the system/Home Manager key distinction and staging precedence,
retained the current first-boot implementation, and corrected the runbook's
new-key proof and data-key retirement sequence. The isolated SOPS exercise used
only disposable synthetic keys; it was not a fleet rotation.

Verification: 26 existing pytest checks passed across `login-startup`,
`kepler-fast-state`, `work-vm`, `work-profile`, and `sbx` in the repository-pinned
Python environment. Documentation checks passed. No host activation, login
policy change, key distribution, or real credential operation occurred.

## Delivery evidence

- Orion: `just dry orion` and `just deploy-rs-preview orion` passed. Reviewed
  closure changes add OpenCode 1.18.29, four profiles, workflows and RTK; no GPU,
  NIC, kernel or storage changes. `just deploy-rs orion` confirmed activation.
  Current system: `z8xjq7c6nc0hxz92vxaiagr59wjnfa7g`; booted system remains
  `f5q7xqcangibzrmnnb044aiqwhq926yh`. No reboot required for this user-tool change.
- Apollo: already running and booted `qz5mfaljrfcgc7j1n57bqvkxcz4rc05i` with all
  four correct GLM 5.3 Flash profiles and successful Home Manager. No redeployment.
- Endeavour: `h1la17hlb9vfcqv0q6pa7lwkg6yqlwlg` activated; Home Manager finished
  successfully at 2026-09-07 23:05:55 UTC; no failed units; Ghostty uses `never`.
  Ten conflicting overlay links were archived losslessly under `~/.local/state/home-manager-overlay-handoffs/2026-09-07-31ksvujl`;
  managed links were restored while the newer Codex 0.153.4/RTK 0.48.0 profile and binaries were retained.
- Pathfinder: tailnet SSH timed out; LAN returned no route to host. Source is
  ready; activation and consumer verification remain gated on host reachability.
- The operator can repeat value-free evidence with
  `just opencode-rollout-status orion` (also `apollo` and `pathfinder`). Remote
  dirty repositories were observed, never read by the build or modified.

## Draft decisions

- Do not restore old Gemini SSH/Syncthing/Herdr declarations or previous GPU/NIC/
  boot policies from mixed canonical patches; newer main owns those migrations.
- Ghostty draft set `mouse-shift-capture=true`, which forwards Shift to the TUI,
  contradicting its selection intent. Use `never`, per the installed Ghostty
  1.3.1 manual. The config parser accepts it; affected-host dry-build gates apply.
- The journald `settings.Journal` draft depends on the separate input upgrade:
  the published flake has no `services.journald.settings` option. Porting it alone
  would break evaluation. Existing retention limits remain unchanged.
- Codex draft adds a second RTK package and broad skill installation. Preserve
  for a separate compatibility review; OpenCode's reviewed RTK packaging already
  exists. NetBird enrollment and additional network/host drafts are not inferred
  from this rollout.

## Complete canonical path disposition

This inventory covers tracked edits and untracked paths reported by Git at the
audit point. It does not reset the index, remove worktrees or delete draft files.

### Reviewed remaining paths (19; dispositions below)

- `.gitignore`
- `docs/README.md`
- `docs/behaviors/endeavour-luks-recovery/recovery.feature`
- `docs/behaviors/recovery-custody/recovery-custody.feature`
- `docs/guides/github-forks.md`
- `docs/guides/orion-display-capture.md`
- `docs/guides/umbrella-sessions.md`
- `docs/implemented/2026-06-30-openbao-root-recovery.md`
- `docs/reference/vault-disaster-recovery.md`
- `justfile`
- `modules/desktop/github-fork-sync.nix`
- `modules/dev/agent-disciplines.md`
- `modules/dev/opencode-agents.md`
- `modules/dev/opencode.nix`
- `modules/networking/netbird-client.nix`
- `modules/profiles/desktop.nix`
- `scripts/capture-orion-display.sh`
- `scripts/deploy-codex-tools.sh`
- `scripts/test_capture_orion_display.py`

### Superseded or mixed host/recovery work; preserve draft, use reviewed main (16)

- `docs/behaviors/kepler-apollo-gpu-exchange/exchange.feature`
- `docs/reference/kepler-apollo-gpu-exchange.md`
- `modules/dev/herdr.nix`
- `modules/hosts/apollo/default.nix`
- `modules/hosts/apollo/hardware.nix`
- `modules/hosts/apollo/k3s-cluster.nix` (removed 2026-09-17 with the host's cluster)
- `modules/hosts/discovery/diagnostics.nix`
- `modules/hosts/endeavour/default.nix`
- `modules/hosts/kepler/default.nix`
- `modules/hosts/kepler/networking.nix`
- `modules/hosts/orion/default.nix`
- `modules/hosts/orion/hardware.nix`
- `modules/ssh.nix`
- `modules/terminal/tmux.nix`
- `tests/apollo-host/test_apollo.py`
- `tests/tmux-persistence/test_session.py`

### Already delivered byte-identically; retain canonical state until explicit cleanup (22)

- `docs/reference/2026-09-07-telemetry-drill.md`
- `modules/dev/graphify-skills/opencode/.graphify_version`
- `modules/dev/graphify-skills/opencode/SKILL.md`
- `modules/dev/graphify-skills/opencode/references/add-watch.md`
- `modules/dev/graphify-skills/opencode/references/exports.md`
- `modules/dev/graphify-skills/opencode/references/extraction-spec.md`
- `modules/dev/graphify-skills/opencode/references/github-and-merge.md`
- `modules/dev/graphify-skills/opencode/references/hooks.md`
- `modules/dev/graphify-skills/opencode/references/query.md`
- `modules/dev/graphify-skills/opencode/references/transcribe.md`
- `modules/dev/graphify-skills/opencode/references/update.md`
- `modules/dev/opencode-commands/codehero.md`
- `modules/dev/opencode-commands/grill.md`
- `modules/dev/opencode-commands/ip.md`
- `modules/dev/opencode-commands/map.md`
- `modules/dev/opencode-commands/party.md`
- `modules/dev/opencode-commands/pl.md`
- `modules/dev/opencode-commands/rv.md`
- `modules/dev/opencode-commands/tdd.md`
- `modules/packages/desktop.nix`
- `modules/packages/shared.nix`
- `tests/apollo-worklab/orion-apollo-roles.feature`

### Deferred together to a reviewed input upgrade (2)

- `flake.lock`
- `modules/services/logrotate.nix`

### Separate Codex/skills draft; preserve, do not install wholesale (52)

- `modules/dev/codex-skills/bmad-editorial-review/SKILL.md`
- `modules/dev/codex-skills/bmad-editorial-review/customize.toml`
- `modules/dev/codex-skills/bmad-editorial-review/references/structure-models.md`
- `modules/dev/codex-skills/bmad-editorial-review/scripts/tests/test_word_metrics.py`
- `modules/dev/codex-skills/bmad-editorial-review/scripts/word_metrics.py`
- `modules/dev/codex-skills/bmad-party-mode/SKILL.md`
- `modules/dev/codex-skills/bmad-party-mode/customize.toml`
- `modules/dev/codex-skills/bmad-party-mode/references/create-party.md`
- `modules/dev/codex-skills/bmad-party-mode/references/mode-agent-team.md`
- `modules/dev/codex-skills/bmad-party-mode/references/mode-auto.md`
- `modules/dev/codex-skills/bmad-party-mode/references/mode-subagent.md`
- `modules/dev/codex-skills/bmad-party-mode/references/party-memory.md`
- `modules/dev/codex-skills/bmad-party-mode/scripts/resolve_party.py`
- `modules/dev/codex-skills/bmad-party-mode/scripts/tests/test_resolve_party.py`
- `modules/dev/codex-skills/cavecrew/README.md`
- `modules/dev/codex-skills/cavecrew/SKILL.md`
- `modules/dev/codex-skills/caveman-commit/README.md`
- `modules/dev/codex-skills/caveman-commit/SKILL.md`
- `modules/dev/codex-skills/caveman-compress/README.md`
- `modules/dev/codex-skills/caveman-compress/SECURITY.md`
- `modules/dev/codex-skills/caveman-compress/SKILL.md`
- `modules/dev/codex-skills/caveman-compress/scripts/__init__.py`
- `modules/dev/codex-skills/caveman-compress/scripts/__main__.py`
- `modules/dev/codex-skills/caveman-compress/scripts/benchmark.py`
- `modules/dev/codex-skills/caveman-compress/scripts/cli.py`
- `modules/dev/codex-skills/caveman-compress/scripts/compress.py`
- `modules/dev/codex-skills/caveman-compress/scripts/detect.py`
- `modules/dev/codex-skills/caveman-compress/scripts/validate.py`
- `modules/dev/codex-skills/caveman-help/README.md`
- `modules/dev/codex-skills/caveman-help/SKILL.md`
- `modules/dev/codex-skills/caveman-review/README.md`
- `modules/dev/codex-skills/caveman-review/SKILL.md`
- `modules/dev/codex-skills/caveman-stats/README.md`
- `modules/dev/codex-skills/caveman-stats/SKILL.md`
- `modules/dev/codex-skills/caveman/README.md`
- `modules/dev/codex-skills/caveman/SKILL.md`
- `modules/dev/codex-skills/rv/SKILL.md`
- `modules/dev/codex-skills/test-driven-development/SKILL.md`
- `modules/dev/codex-skills/test-driven-development/testing-anti-patterns.md`
- `modules/dev/codex-tools.nix`
- `modules/dev/codex.nix`
- `modules/dev/graphify-skills/codex/.graphify_version`
- `modules/dev/graphify-skills/codex/SKILL.md`
- `modules/dev/graphify-skills/codex/references/add-watch.md`
- `modules/dev/graphify-skills/codex/references/exports.md`
- `modules/dev/graphify-skills/codex/references/extraction-spec.md`
- `modules/dev/graphify-skills/codex/references/github-and-merge.md`
- `modules/dev/graphify-skills/codex/references/hooks.md`
- `modules/dev/graphify-skills/codex/references/query.md`
- `modules/dev/graphify-skills/codex/references/transcribe.md`
- `modules/dev/graphify-skills/codex/references/update.md`
- `tests/codex-skills/test_global_skills.py`

### Corrected and delivered by this slice (1)

- `modules/terminal/ghostty.nix`

## Hunk-level decisions for remaining paths

- `.gitignore`: anchor `/references/` would expose vendored nested skill references;
  useful only with the separate skill-vendoring draft, retain with that work.
- `docs/README.md`: mixed index of delivered GPU/umbrella changes, recovery gates,
  excluded fork sync and concurrent tooling. Apply only this slice's targeted rows.
- OpenBao recovery docs plus `recovery-custody.feature`: accepted and ported. They
  correctly separate Kepler host-loss copies from outside-home Voyager/B2 and
  require B4/S1 witness evidence; no new credential or standing root token.
- `endeavour-luks-recovery/recovery.feature`: sound manual staffed-console contract
  linked to the canonical proposal, not runnable proof. Preserve pending physical
  passphrase/escrow witnesses; no boot/keyslot mutation is implied.
- Fork-sync module, guide and `profile-desktop` import: excluded. The list explicitly
  includes corporate repositories and LMCache, Sail and Airflow, which the user
  deferred. Native Git fast-forward safeguards do not authorize that scope; retain
  manual credential provisioning boundary.
- `umbrella-sessions.md`: superseded by delivered Orion/Apollo native sessions;
  preserve published paths instead of replacing with older mixed branch text.
- `opencode.nix`: superseded. Draft restores direct Go credential fallback,
  experimental baseline plugins and DeepSeek default, and drops delivered gateway
  headers/profiles. This conflicts with the accepted simplified GLM configuration.
- `opencode-agents.md` plus `agent-disciplines.md`: separates instruction prose,
  but coupled Codex/OpenCode installation is concurrent workflow work. Keep current
  reviewed routing and discipline content until that separate change is reviewed.
- NetBird module: explicit external-network client exception, interactive enrollment;
  a distinct network feature, not OpenCode or a homelab fleet fix. Retain unactivated.
- `justfile`: useful older Apollo-builder/host recipes have newer reviewed owners;
  new Headroom proxy experiments, Codex-only deploy and display capture are separate
  concurrent work. No wholesale replacement of current recovery/deploy recipes.
- Orion capture guide/scripts/tests and `deploy-codex-tools.sh`: arrived during this
  reconciliation from another active task; preserve and leave to that owner.
