# Desktop reconciliation and OpenCode rollout

**Status:** Endeavour and Orion activated; Orion and Apollo home/work real tool checks pass.
Pathfinder remains unreachable. Canonical drafts retained unchanged; original audit against `1ed67c9`.

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
- `modules/hosts/apollo/k3s-cluster.nix`
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
