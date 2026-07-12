## Behavioral guidelines

These bias toward caution over speed; for trivial tasks, use judgment.

### Think before coding

- State assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them — don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

### Simplicity first

Minimum code that solves the problem; nothing speculative. No features
beyond what was asked, no abstractions for single-use code, no
"flexibility" that wasn't requested, no error handling for impossible
scenarios. Ask: "Would a senior engineer say this is overcomplicated?"
If yes, simplify.

### Surgical changes

Every changed line should trace directly to the request.

- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- Remove imports/options/modules that **your** change made unused; mention
  (don't delete) pre-existing dead code.

### Goal-driven execution

Transform tasks into verifiable goals and loop until verified. In this
repo, verification means the **Verify changes** section below: lint +
fmt-check, `just dry <host>` / toplevel `--dry-run` for touched hosts, eval
spot-checks for refactors that must be behavior-preserving, and post-switch
service checks for deploys. For multi-step work, state a brief plan with a
verify step per item.

## Architecture orientation (read before editing modules)

This flake is **dendritic**: `flake.nix` is just `flake-parts.mkFlake` +
`import-tree ./modules`. Every `.nix` file under `modules/` is auto-imported
as a flake-parts module — there are no aggregator `default.nix` import lists.
Files whose path contains a segment starting with `_` are skipped by
import-tree (`_hw-generated.nix` is imported explicitly by host hardware
modules). The full contract — registration, naming, `_` helpers — lives in
`docs/reference/dendritic-contract.md` and is checked by `just structure-check`.

- Feature modules register themselves under `flake.modules.nixos.<name>` /
  `flake.modules.home.<name>` (deferredModule). Hosts compose them via
  `imports = [ m.nixos.<name> … ]` where `m = config.flake.modules`.
- Shared values flow through **top-level options** (`modules/meta.nix`:
  `username`, `email`, `configPath`; `modules/secrets.nix`:
  `syncthingDeviceIDs`) — never `specialArgs`.
- Hosts are produced from `configurations.nixos.<host>.module`
  (`modules/configurations.nix`). A host's `default.nix` should stay thin:
  import list + genuinely host-specific config.

### Module naming convention

- `profile-*` — composition profiles (`profile-base` minimal fleet-wide,
  `profile-desktop` GUI/workstation, `profile-server` headless).
- `<host>-*` — host-scoped aspects (`kepler-nas`, `pathfinder-hardware`).
- bare names — fleet-wide feature aspects (`alloy`, `firewall`,
  `btrfs-snapshots`, `syncthing-fleet` which generates all
  `<host>-syncthing` modules from one topology table).
- Don't create per-host copies of a feature; parameterize one module
  (see `modules/services/syncthing-fleet.nix`).

### Things that bite

- **New files must be `git add`ed before any `nix` command sees them** —
  flake eval ignores untracked files; the error is a misleading
  "attribute missing".
- `profile-base` is intentionally minimal. GUI/workstation concerns
  (xserver, peripherals, power/TLP, thunderbolt, vms, containers,
  file-systems) live in `profile-desktop`; servers import individual pieces
  explicitly (see orion/kepler `default.nix`).
- `modules.upgradeHealthCheck.criticalUnits` guards unattended upgrades;
  overriding it **replaces** the default — re-list sshd/tailscaled.

## Verify changes

Before claiming done: `just lint && just fmt-check`, then `just dry <host>`
for touched hosts (or `nix build .#nixosConfigurations.<host>.config.system.build.toplevel --dry-run`
without sudo). For doc edits, `just docs-check` verifies every in-repo markdown
link resolves. `just check` runs the full pre-flight (docs-check + lint +
fmt-check + dry-all). CI evaluates all five hosts on push/PR. After a remote
`switch`, verify services per the rules below — a green rebuild is not proof
the service came up.

## Docs map

`docs/README.md` is the index. Operational truth lives in `justfile`
recipes; `docs/` explains why. If doc and recipe disagree, the recipe wins.
Layout is typed:

- `docs/guides/` — how-to walkthroughs (`install.md`, `obsidian.md`).
- `docs/reference/` — operational "why" + as-built (kepler AI serving, kepler
  ZFS, k3s platform status, harbor registry).
- `docs/implemented/` — shipped designs, kept as the record.
- `docs/proposals/` — active RFCs only (`YYYY-MM-DD-<slug>.md`); finished ones
  graduate to `implemented/` or are deleted. Every doc carries a `**Status:**`
  line; the README index mirrors it. Run `just docs-check` after doc edits.

## Commit policy

Never add `Co-Authored-By: Claude …` (or any other Anthropic attribution) to
commit messages or PR bodies in this repo. Commits should read as if a human
authored them; the only signature is the configured `git user.name` /
`user.email`.

The universal **Defensive Commit Rules** from `~/.claude/CLAUDE.md` apply
here. The items below extend (not relax) them with repo-specific patterns.

## Repo-specific never-commit patterns

- **Nix build artifacts**: `result`, `result-*` symlinks, `.direnv/`, anything
  under `/nix/store` paths. These are reproducible — they belong on disk, not
  in git.
- **Secrets are sops-encrypted only**: `*.yaml`/`*.json` files containing
  unencrypted credentials must never land in this repo. Verify
  `secrets/*.yaml` is sops-encrypted (`sops: …` block present) before staging.
- **VM / disk images**: `*.qcow2`, `*.img`, `*.iso`, `*.vmdk`. Use a fixture
  fetcher in `flake.nix` instead.
- **Hardware-specific generated config**: `hardware-configuration.nix` is per
  host — confirm before committing changes that came from
  `nixos-generate-config` on another machine.
- **Compiled BMAD assets**: anything under `_bmad/.cache/` or runtime state
  produced by `/bmalph-*` commands.

## Remote actions — autonomous, but channelled

Claude **may** update remote hosts (`pathfinder`, `kepler`, `discovery`,
`orion`, `laptop`, hermes targets, servarr targets) without prompting per
command, **on the strict condition** that every remote-touching action goes
through a documented entry point:

- `just` recipes in `desktop-nixos/justfile` (`just deploy …`,
  `just switch-<host>`, `just pull-servarr <host>`, `just kick-stack <host>
  <stack>`, etc.)
- `just` recipes in sister repos (`servarr/justfile`,
  `hermes-flake/Justfile`).
- Deploy docs in `docs/` and `references/` — follow them verbatim. If a doc
  and a recipe disagree, the recipe wins (the doc is stale; flag it).

Forbidden even with the above autonomy:

- Raw `nixos-rebuild switch --target-host …` invocations that bypass
  `just deploy`. The recipe carries the substitutes/sudo/port flags — open
  coding it loses those guarantees.
- Editing files **on** a remote host over SSH instead of changing the source
  repo and re-deploying. Configuration must always flow `repo → deploy`.
- Anything destructive on the remote (`rm`, `docker volume rm`,
  `zpool destroy`, `nixos-rebuild --rollback` past a known-good generation,
  partition / LUKS / sops key operations) — those still require explicit
  user confirmation in the turn.
- Touching unmerged in-progress state on a remote host (`/srv/work`,
  databases mid-migration). If unsure whether state is live, ask.

Verification expectations:

- Before `switch`, run `just dry <host>` (or repo equivalent) and skim the
  diff for surprises.
- After `switch`, verify with `systemctl status` / `journalctl -u` / curl on
  the affected service. A green `nixos-rebuild` is not proof the service
  came up.

## Cross-repo synergies

This flake (`desktop-nixos`) is the source of truth for host system
configuration. **Eleven** sister repos plug into it. Each is exposed as a gitignored symlink
under `references/repos/` for quick local access (the real working trees live at
`~/Documents/erik/...`):

```
references/repos/servarr               → ~/Documents/erik/servarr            (home compose workloads)
references/repos/homelab-gitops        → ~/Documents/erik/homelab-gitops     (lab k8s workloads, Argo CD)
references/repos/homelab-iac           → ~/Documents/erik/homelab-iac        (UniFi/network substrate)
references/repos/hermes-flake          → ~/Documents/erik/hermes-flake       (hermes-agent package + module)
references/repos/hermes-skills         → ~/Documents/erik/hermes-skills      (hermes skill content)
references/repos/opencode-flake         → ~/Documents/erik/opencode-flake      (opencode package + HM module; flake input)
references/repos/home-assistant-config → ~/Documents/erik/code/home-assistant-config  (HA app config)
references/repos/klipper-biqu          → ~/Documents/erik/klipper-biqu       (printer config/state)
references/repos/kindle-dash           → ~/Documents/erik/kindle-dash        (e-ink dashboard; standalone OSS — P4)
references/repos/ha-agent              → ~/Documents/erik/ha-agent           (PT-BR HA tool-caller fine-tune; local-only)
references/repos/codex-flake           → ~/Documents/erik/codex-flake        (codex CLI package + HM module; flake input)
```

Justfile recipes resolve through these symlinks (`readlink -f
references/repos/servarr`); never hard-code the absolute path.

### Layered model + one owner per concern (SSOT/SRP)

Three clean layers: **network/physical** (`homelab-iac`) → **host/cluster
substrate** (`desktop-nixos`, incl. k3s microvms) → **workloads** (`servarr`
compose **and** `homelab-gitops` k8s — two *peer* permanent envs, not a
migration). Full rationale + decisions D1–D9 live in
`docs/implemented/2026-06-29-repo-ssot-srp.md` (and the P3 secrets sub-RFC). One
owner per concern — change a fact in its owner, consumers vendor/pin it (D9):

| Concern | Owner (SSOT) |
|---------|--------------|
| Network: VLAN/WLAN/**DHCP reservations**/static DNS/Tailscale ACL/Cloudflare tokens | `homelab-iac` |
| Host OS + fleet system config; **hosts/roles/addressing** (`fleet.json`) + **domains** (`fleet.ingress`/`fleet.services`) | `desktop-nixos` |
| Cluster substrate (k3s microvms, NFS) | `desktop-nixos` (Nix-native, D6) |
| Home / always-on household workloads (compose) | `servarr` |
| Lab / prod-mimic / ephemeral workloads (k8s, Argo; vcluster for throwaways) | `homelab-gitops` |
| **Runtime** secrets (docker via vault-agent, k8s via ESO, iac via provider) | platform **Vault** @discovery (D5) |
| **Host/build/bootstrap** secrets (SSH/age keys, wifi/restic, Vault+iac bootstrap) | **sops** (D5) |
| Container images: private SSOT / public OSS | **Harbor** / **GHCR** (D7) |
| hermes-agent software (package + module) | `hermes-flake` |
| hermes skill content | `hermes-skills` |
| HA app config · printer config/state | `home-assistant-config` · `klipper-biqu` |
| Kindle dashboard image (standalone OSS) | `kindle-dash` (D8) |

D1–D9 one-liners: D1 two peer envs (home=servarr, lab=gitops), placed by purpose;
D2 lab self-contained (own obs/ingress/CoreDNS), only the network is shared; D3
ephemeral lab = vcluster; D4 lab on the home LAN; D5 shared platform Vault =
runtime-secret SSOT, sops = root-of-trust + host/build/bootstrap only; D6 VMs stay
Nix-native (microvm.nix); D7 Harbor = private SSOT both envs pull, GHCR = public
OSS; D8 kindle-dash = standalone OSS (owns build+scripts, publishes image); D9
**publish-and-pin** — SSOT owner publishes a versioned artifact, consumers
vendor/pin it; no live cross-repo reads at build/apply (runtime Vault fetch is the
one sanctioned runtime dep).

### SRP placement — where does a new thing go?

1. **Network/DNS/DHCP/reservation/ACL/Cloudflare** → `homelab-iac`.
2. **Host OS aspect, cluster substrate, or a VM** → `desktop-nixos`.
3. **A workload (service/app):**
   - household / always-on home service → **`servarr`** (compose).
   - study / prod-mimic / ephemeral experiment → **`homelab-gitops`** (k8s; vcluster for throwaways).
4. **App config of an existing appliance** (HA, printer) → that appliance's repo
   (`home-assistant-config`, `klipper-biqu`) — this flake owns its OS, not its config.
5. **A fleet-wide *fact*** (host IP/MAC/role, ingress zone, public/cross-host
   service) → `desktop-nixos` `modules/meta.nix` (`fleet.*`) → `fleet.json`.

No forced migration of existing home stacks; peer envs are placed by **purpose**,
not absorbed.

### `servarr` — container stacks on homelab hosts

- Lives at `~/Documents/erik/servarr`. Reachable in-repo via
  `references/repos/servarr`.
- **Delivery is git-only** (since 2026-06-29). Each host's `servarr-pull`
  service does `git fetch + reset --hard origin/main` and decrypts `.env.sops`
  → `.env`. rsync (`sync-servarr`/`sync-stack`) was retired — it dirtied the
  git tree and silently broke the pull. **git is authoritative**: never
  hand-edit the servarr clone on a host; it is reset to origin on the next
  pull.
- Flow: edit `references/repos/servarr/machines/<host>/` → `just prep-servarr`
  (refresh generated SOUL.md mirror) → commit + push in the servarr repo →
  `just pull-servarr <host>` → `just kick-stack <host> <stack>` to **recreate**
  (not restart) containers whose compose/env changed. See
  `memory/servarr_env_flow.md`.
- **Branch-aware**: `just pull-servarr <host>` deploys `origin/main`. Pass a
  branch (`just pull-servarr <host> feature/x`) to deploy a feature branch for
  testing — the host pins it via an untracked `.deploy-branch` pointer (sticky
  across reboots). Merge to main, then `just pull-servarr <host>` (no branch) to
  return. Same pattern can front other host-pull repos.
- Targets today: `kepler`, `discovery`, `orion`. Each host owns a stack
  directory under `references/repos/servarr/machines/<host>/`.

### `hermes-flake` — hermes-agent package + NixOS module

- Lives at `~/Documents/erik/hermes-flake`. Reachable in-repo via
  `references/repos/hermes-flake`. Vendored as a flake input.
- Provides `packages.hermes-agent` and `nixosModules.hermes-agent`. Consumed
  by `kepler` (AI serving host) and any other host running hermes.
- Upstream version bumps: run `just update-check` then `just update` inside
  `hermes-flake`, build there (`just build`), commit, then update
  `desktop-nixos`'s `flake.lock` (`nix flake lock --update-input
  hermes-flake`) and deploy with `just switch-kepler`.
- TTS / LiteLLM routing nuances are recorded in recent commits and in
  `docs/reference/kepler-ai-serving.md` — follow those before changing wiring.

### `code/home-assistant-config` — HA config on the HA host

- Lives at `~/Documents/erik/code/home-assistant-config`. Reachable in-repo
  via `references/repos/home-assistant-config`. Pushed to the HA instance
  via its own deploy flow (the HA host pulls from the repo; see that repo's
  `README.md` and `hooks/`).
- PR flow: push branches, **do not auto-merge** — wait for the user's
  explicit "merge" (see `memory/feedback_ha_pr_flow.md`).
- Voice-assistant integration touches `kepler` (LiteLLM / piper-openai /
  whisper). When changing voice routing on the HA side, cross-check ports
  and service names against `desktop-nixos/machines/kepler/` and
  `docs/reference/kepler-ai-serving.md`.
- See `memory/ha_voice_assistant.md` for locked decisions and the active
  Phase-1 branch.

### `klipper-biqu` — BIQU B1 printer config (Klipper + OrcaSlicer)

- Lives at `~/Documents/erik/klipper-biqu`. Reachable in-repo via
  `references/repos/klipper-biqu`.
- Versions the printer's two disjoint config sets: `printer_data/config/`
  (Klipper — `printer.cfg`, `mainsail.cfg`, macros; pushed by the
  `klipper-config-backup` service **on the Pi**, which is safe for this shared
  repo — it mirrors only `printer_data/config/` and never touches
  `orcaslicer/`) and `orcaslicer/` (OrcaSlicer presets; pushed from the laptop
  via that repo's `just orca-sync`).
- Klipper host: the NixOS `archinaut` fleet host (RPi 3 **Model B+**), on WiFi
  **`192.168.10.225`** (DHCP-reserved on the wlan0 MAC; wired retired). As-built
  hardware/calibration reference lives in that repo's `references/README.md`.
- **NixOS migration DONE** (2026-06-21): the Pi is the fleet `archinaut` host
  running `services.klipper`/`moonraker`/`mainsail` with **kernel-direct boot**
  (no u-boot — board is a 3B+, MCU on `/dev/ttyS1`). aarch64 closure built on
  orion (binfmt), the Pi substitutes. **Services-only**: NixOS owns OS +
  MCU-firmware *build* + package versions; **all** config — Klipper
  `printer.cfg`, Mainsail `mainsail.cfg`, OrcaSlicer presets — lives in the
  `klipper-biqu` repo, never in Nix (exception: `moonraker.conf` is declarative
  `services.moonraker.settings`). The Pi's `/var/lib/klipper` is a mutable
  working copy round-tripped via the `klipper-config-backup` service so
  `SAVE_CONFIG`/Mainsail edits survive a reflash. See
  `docs/implemented/2026-06-20-archinaut-kernel-direct-boot.md`; calibration
  docs in the `klipper-biqu` sister repo (`references/`). It is in the coupling
  map below.
- This repo is **config/state only** — no flake input, no NixOS module
  today. Touch it like `home-assistant-config`: it owns the app config, this
  flake owns the host OS.

### `homelab-iac` — declarative UniFi network (OpenTofu + Terragrunt)

- Lives at `~/Documents/erik/homelab-iac`. Reachable in-repo via
  `references/repos/homelab-iac`. Remote:
  `git@github.com:ErikBPF/homelab-iac.git`.
- Source of truth for the **network the fleet lives on**: VLANs, WLANs, static
  DNS, and **DHCP fixed-IP reservations** on the home UDM (`192.168.10.1`), via
  the `filipowm/unifi` provider (Terragrunt units per stack, config under
  `unifi/`). Two envs: `home` (live) and `lab` (stub).
- **Addressing contract** with this flake: the reservations there assign the
  IPs hosts use here — `kepler .230`, `homeassistant .115`, `archinaut .225`,
  `nix-erik .125`, … Change a host's IP in one repo → update the matching
  reservation in the other, or DHCP and the host config disagree.
- **Config/state only** — no flake input, no NixOS module. Touch it like
  `home-assistant-config`/`klipper-biqu`: it owns the network, this flake owns
  the hosts. Apply **only from a wired LAN host** (Wi-Fi changes can self-lock);
  state is local + encrypted. See its `README.md`.

### `homelab-gitops` — lab k8s workloads (Argo CD)

- Lives at `~/Documents/erik/homelab-gitops`. Reachable via
  `references/repos/homelab-gitops`. **Not Nix** (prod-mimic, servarr-style repo).
- Owns the **lab** env (D1): k8s workloads synced by Argo CD onto the kepler k3s
  cluster, with ESO→Vault@discovery for secrets, in-cluster Prometheus/Grafana/
  ingress/CoreDNS (D2 — lab is self-contained; only the *network* is shared).
  Ephemeral experiments use **vcluster** (D3). Lab hostnames live here, not in the
  fleet domains SSOT. See `memory/platform_gitops_repo.md`.

### `hermes-skills` — hermes skill content

- Lives at `~/Documents/erik/hermes-skills`. Reachable via
  `references/repos/hermes-skills`. **Content, not package** (kept separate from
  `hermes-flake` by design). Synced to a host and mounted read-only into the
  hermes container via `skills.external_dirs` — `just sync-hermes-skills <host>`,
  then recreate the stack so it re-scans.

### `kindle-dash` — Kindle e-ink wall dashboard

- Lives at `~/Documents/erik/kindle-dash`. Reachable via
  `references/repos/kindle-dash`. See `memory/kindle_dashboard.md`.
- **Target state (D8, P4 — in progress):** standalone OSS project that owns its
  container **build + device scripts** and publishes the image (**GHCR** public +
  **Harbor** private, D7). Consuming stacks (servarr) only *reference* the pinned
  digest + supply deploy config. Strip homelab-specific deploy glue out of it.

### `opencode-flake` — opencode package + Home-Manager module

- Lives at `~/Documents/erik/opencode-flake`. Reachable via
  `references/repos/opencode-flake`. Remote
  `git@github_erikbpf:ErikBPF/opencode-flake.git`.
- **Vendored as a flake input**, but *not* pinned to the local tree — consumed via
  **FlakeHub** (`url = "https://flakehub.com/f/ErikBPF/opencode-flake/*"`). Provides
  the opencode package (`withPackage`) + a Home-Manager module; the **laptop** dev
  env is fully HM-managed off it (config, permissions, rtk plugin). Ships a **daily
  auto-merge lane** + FlakeHub publish; no Cachix (the orion cache covers the fleet).
- Bump flow like `hermes-flake`: land upstream in the leaf → the daily lane republishes
  to FlakeHub → `nix flake update opencode-flake` here → `just build laptop`. Gotchas
  (HM crash on `package=null` HM#9589, placeholder jsonschema nixpkgs#537917, rtk=plugin
  not markdown, permissions need `dag.entryAfter`): `memory/opencode_flake_rfc.md`.

### `codex-flake` — codex CLI package + Home-Manager module

- Lives at `~/Documents/erik/codex-flake`. Reachable via
  `references/repos/codex-flake`. Remote
  `git@github_erikbpf:ErikBPF/codex-flake.git`.
- **Vendored as a flake input via FlakeHub** (`url =
  "https://flakehub.com/f/ErikBPF/codex-flake/*"`, pinned in `flake.lock`). Provides
  `packages.codex`, a Home-Manager module (`homeManagerModules.{default,codex-profile}`
  + a `withPackage` helper), and a `codex-latest` overlay. Twin of `opencode-flake`;
  consumed by the **laptop** dev env via `modules/dev/codex.nix`
  (`flake.modules.home.codex`, imported by `profile-desktop`).
- Ships **official prebuilt openai codex binaries** (4 platforms, hourly build, required
  package-build gate). Bump flow like `opencode-flake`/`hermes-flake`: land upstream in the
  leaf → FlakeHub republishes → `nix flake update codex-flake` here → `just build laptop`.

### `ha-agent` — PT-BR Home Assistant tool-caller fine-tune

- Lives at `~/Documents/erik/ha-agent`. Reachable via `references/repos/ha-agent`.
- Trains a small offline **PT-BR tool-calling** model for HA voice commands
  (lights, whole-house, forecast, escalate-to-reasoner, clarify/decline/noop).
  The intended runtime home is the **kepler AI-serving** host behind LiteLLM,
  as the fast local first-responder that escalates hard queries to the 35B —
  the natural language backend for the HA voice-assistant (see
  `docs/proposals/2026-07-02-home-assistant-ai-consolidation.md` and
  `docs/reference/kepler-ai-serving.md`).
- **Local-only, never pushed public:** the corpus embeds real home `entity_id`s.
  Secrets (LiteLLM/Kaggle keys) stay in a gitignored `.env`, not committed.
- **Config/data + model repo — no flake input, no NixOS module** (today). Touch
  it like `home-assistant-config`/`klipper-biqu`: it owns the model + corpus,
  this flake owns the host that will serve it. Training runs on **orion** (RX
  9070 XT, fp16 LoRA only — no bnb on gfx1201) and **Kaggle** (big models).
  Iterate-small-then-big loop + all training gotchas:
  `ha-agent/docs/LOOP-improve-4b.md` and `docs/RUNBOOK-corpus-and-train.md`.

### Coupling map

```
desktop-nixos (system config + fleet SSOT: fleet.json hosts/ingress/services)
├── inputs.servarr      → home compose workloads on kepler/discovery/orion
├── inputs.hermes-flake → hermes-agent (+ hermes-skills content, git-synced)
├── inputs.opencode-flake → opencode pkg + HM module (FlakeHub); laptop dev env
├── inputs.codex-flake  → codex CLI pkg + HM module (FlakeHub); laptop dev env
├── k3s microvms (kepler) ← homelab-gitops syncs lab k8s workloads via Argo CD
├── deploys / hosts     → kepler also serves HA voice backend
│                         ↑
│                         home-assistant-config (HA app config)
├── archinaut host      → klipper-biqu owns /var/lib/klipper config (git source-of-truth)
├── kindle-dash         → standalone OSS image (GHCR+Harbor); servarr references it
└── kepler AI serving   ← ha-agent trains the PT-BR HA tool-caller LiteLLM will front (local-only)

homelab-iac (UniFi network)  ← the substrate all the above run on:
  DHCP reservations pin every host's IP; static DNS pins service hostnames —
  both VENDOR desktop-nixos's fleet.json (D9 publish-and-pin), re-synced on a
  deliberate bump. desktop-nixos owns the hosts; homelab-iac owns the network.
```

Rule of thumb: when a change touches more than one of these repos, land the
**leaf** repo first (hermes-flake / servarr / home-assistant-config /
klipper-biqu), then bump the input / sync, then deploy from `desktop-nixos`.

## Per-slice TDD mechanics (nixos-flake variant)

Spicyphus per-slice loop is canonical here, per global `AGENTS.md`. This
section pins repo specifics; overrides global defaults only where this
flake has firmer convention.

**Per-slice artifacts live under** `docs/behaviors/<slice-slug>/`:

- `behavior.md` — seed, human-only, kept
- `test-contract.md` — refine (architect, GLM)
- `lessons.md` — postmortem, human, kept

If a slice spans sister repos, `behavior.md` lives in the **leaf** repo the
change lands in first (per `Rule of thumb` above); this flake's
`behavior.md` cross-references the leaf's, never duplicates.

**Test framework by surface (red/green gate):**

- Nix expressions (`modules/**`, `flake.nix`): red/green = `just dry <host>`
  for every touched host + `nix flake check --no-link` for the closure. The
  just recipe is authoritative (per `Recipe wins` rule); raw
  `nixos-rebuild … --target-host` is **forbidden** (see `Remote actions`).
- Full-system module changes: dry-build first (`just dry <host>`), inspect
  diff, `just switch-<host>`, then post-switch verify per the existing
  `Verify changes` section.
- Shell scripts under `modules/**`: `shellcheck` then `bats` for behavior
  lock. Repo has no `bats` today — when a first `behavior.md` calls for it,
  add `bats` as a flake devshell input **before** writing tests (RFC step
  first; no speculative infra).

**Multi-agent dispatch for nixos-flake slices:**

- Architect (GLM, `opencode-go/glm-5.2`): grill, draft `test-contract.md`,
  run seed-integrity diff. Model bind lives in `modules/dev/opencode.nix`
  via HM.
- General (MiMo pro, `opencode-go/mimo-v2.5-pro`): write red tests + green
  impl. Source-of-trUTH: agent edits `modules/**` + `flake.nix` only —
  never edits `/nix/store` or remote host files (re-iterate the `Remote
  actions → repo → deploy` rule).
- Verify: `just dry <host>` MUST pass before green claim; `nix flake
  check` final gate before PR.
- Parallel dispatch: spawn 1..N `@general` agents in one message for
  independent impl slices (each owns one module/sub-feature).

**Self-improve cap:** 3 retries per global rule; after exhaustion, halt +
report blockers to user. Do not silently edit `behavior.md` to fix infra
failures — re-seed if behavior was wrong, fix infra if behavior was right
but the build broke.

**HM rebuild is the deploy step for ethos + agent routing changes:** edit
`modules/dev/opencode-agents.md` (ethos) and `modules/dev/opencode.nix`
(opencode.json + the per-agent `agent` block), then `just build laptop` so
the `/nix/store` copy + `~/.config/opencode/AGENTS.md` symlink refresh.
Never hand-edit `~/.config/opencode/AGENTS.md` or
`~/.config/opencode/opencode.json` directly — both are `/nix/store`
symlinks managed by Home-Manager via `opencode-flake`.
