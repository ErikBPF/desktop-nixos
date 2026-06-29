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
  `just switch-<host>`, `just sync-servarr <host>`, `just sync-stack <host>
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
configuration. Five sister repos plug into it. Each is exposed as a
gitignored symlink under `references/repos/` for quick local access (the
real working trees live at `~/Documents/erik/...`):

```
references/repos/servarr               → ~/Documents/erik/servarr
references/repos/hermes-flake          → ~/Documents/erik/hermes-flake
references/repos/home-assistant-config → ~/Documents/erik/code/home-assistant-config
references/repos/klipper-biqu          → ~/Documents/erik/klipper-biqu
references/repos/homelab-iac           → ~/Documents/erik/homelab-iac
```

Justfile recipes resolve through these symlinks (`readlink -f
references/repos/servarr`); never hard-code the absolute path.

### `servarr` — container stacks on homelab hosts

- Lives at `~/Documents/erik/servarr`. Reachable in-repo via
  `references/repos/servarr`.
- `just sync-servarr <host>` rsyncs
  `references/repos/servarr/machines/<host>/` to
  `erik@<host>:/home/erik/servarr/machines/<host>/`. Excludes `.env` and
  `.env.sops` — those flow through a separate `just push-env <host>` path.
- After a sync, **recreate** (not restart) any containers whose env or
  compose file changed: `docker compose up -d --force-recreate <service>`.
  See `memory/servarr_env_flow.md`.
- Targets today: `kepler`, `discovery`, `orion`. Each host owns a stack
  directory under `references/repos/servarr/machines/<host>/`.
- When adding a new stack: edit
  `references/repos/servarr/machines/<host>/`, run `just sync-stack <host>
  <stack>`, then bring it up on the host.

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

### Coupling map

```
desktop-nixos (system config)
├── inputs.servarr      → containers on kepler/discovery/orion
├── inputs.hermes-flake → hermes-agent on kepler
├── deploys / hosts     → kepler also serves HA voice backend
│                         ↑
│                         home-assistant-config (HA app config)
└── (planned) archinaut host → klipper-biqu seeds /var/lib/klipper/config
                               klipper-backup keeps it as git source-of-truth

homelab-iac (UniFi network)  ← the substrate all the above run on:
  DHCP reservations pin every host's IP; static DNS pins service hostnames.
  desktop-nixos owns the hosts; homelab-iac owns the network they live on.
```

Rule of thumb: when a change touches more than one of these repos, land the
**leaf** repo first (hermes-flake / servarr / home-assistant-config /
klipper-biqu), then bump the input / sync, then deploy from `desktop-nixos`.
