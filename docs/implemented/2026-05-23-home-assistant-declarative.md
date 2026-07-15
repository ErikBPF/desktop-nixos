# Home Assistant as a First-Class Citizen

**Date:** 2026-05-23
**Status:** Implemented — Phase 1 shipped; HAOS retained by decision (2026-07-14)
**Owner:** erik
**Target host:** `discovery`

---

## 1. Outcome

Phase 1 shipped in the `home-assistant-config` repository. Home Assistant app
configuration, automations, scripts, blueprints, dashboards, and vendored custom
components now live in Git. CI validates changes, workstation changes flow through
PRs, and HAOS creates reviewable snapshot PRs for UI-managed changes.

HAOS remains the runtime appliance on `discovery`. The fleet tracks its addressing
and declarative libvirt definition; `home-assistant-config` owns application config.
This boundary matches the fleet SSOT/SRP contract.

Migration to Container or NixOS is deferred without a target date. Reconsider only
when concrete HAOS operational pain outweighs Supervisor/add-on convenience and the
state, USB/Zigbee, backup, and rollback migration risks.

## 2. Original goal

Promote the Home Assistant deployment from an opaque HAOS VM to a fully version-controlled, declarative subsystem that lives alongside the existing NixOS + servarr (compose) configuration.

Concretely:

- **Config-as-code** — every YAML file, blueprint, dashboard, and automation under a Git repo on GitHub.
- **Declarative integrations/plugins** — additions to HA happen via a PR to a Nix file or a tracked YAML file, not by clicking in the UI.
- **Declarative automations** — Nix or Git is the source of truth; UI edits are either banned or auto-committed.
- **CI** — `ha core check_config` runs on every PR before it can reach the live instance.
- **Reproducibility** — nuking the VM/container and rebuilding yields the same instance.

---

## 3. Original baseline

| Item | Where |
|---|---|
| HAOS VM definition | `modules/hosts/discovery/haos.nix` + `haos-domain.xml` |
| Disk image | `/home/erik/vault/vms/haos_ova-17.1.qcow2` (libvirt, qcow2, opaque) |
| Network | bridge `br0` → DHCP-reserved `192.168.10.115` |
| USB passthrough | Silicon Labs CP210x (Zigbee/Z-Wave) |
| Supervisor / Add-ons | Provided by HAOS (Mosquitto, ESPHome, Studio Code Server, etc.) |
| Backups | None automated — qcow2 sits on `vault/` |
| Git | **None** — `/config` inside HAOS is not under version control |
| servarr pattern (reference) | `homelab.compose.stacks` in `modules/hosts/{orion,discovery}/compose.nix` with bind-mounted dirs under `/home/erik/servarr/machines/<host>/` |

**Historical gap:** HA application config was not version-controlled. Fleet state now
spans multiple owner repositories, so full recovery is not a single
`git clone && nixos-rebuild`; each owner publishes or delivers its own artifact or
configuration.

---

## 4. Options considered

Three paths, in increasing order of "Nix-native" purity and decreasing order of HAOS-feature parity.

### Option A — Keep HAOS VM, add Git-as-source-of-truth on `/config`

Lowest risk. HAOS keeps Supervisor + Add-ons. We treat `/config` inside HAOS as a working tree of a GitHub repo (`erik/home-assistant-config`, private).

- Initialise `git` inside HAOS `/config` via Studio Code Server terminal.
- Restructure config: split `configuration.yaml` into folders (`automations/`, `scripts/`, `packages/`, `blueprints/`, `dashboards/`), all `!include`-d from the root file.
- `secrets.yaml`, `.storage/`, DB files added to `.gitignore`.
- SSH deploy key with **write** access (push) configured inside the VM.
- Daily HA-side automation runs `backup2git.sh` at 02:00, committing UI-driven changes — this preserves the "click in UI" workflow while still producing a git history.
- GitHub Actions workflow runs `ha core check_config` on every push to `main`.
- Optional: a separate "puller" script that runs `git pull --ff-only` on `/config` after the GHA job passes and emits a Reload event.

**Pros:** No service downtime, no add-on loss, immediate version control + rollback, smallest change footprint.
**Cons:** HAOS itself remains opaque (still a qcow2 blob). Plugins (HACS / custom integrations) are still installed via UI clicks unless we also vendor them into the repo under `custom_components/`.

### Option B — Replace HAOS with NixOS `services.home-assistant` module on `discovery`

Most Nix-idiomatic. HA Core runs as a systemd unit on `discovery`, all config is generated from Nix attribute sets.

- Add `modules/services/home-assistant.nix` mirroring the servarr pattern (toggleable via `homelab.homeAssistant.enable`).
- Use `services.home-assistant.config = { ... }` for fully declarative YAML; mix with `"automation ui" = "!include automations.yaml"` to keep UI-authoring as an escape hatch.
- `services.home-assistant.extraComponents = [ "zha" "esphome" "met" ... ]` resolves Python deps automatically.
- `services.home-assistant.customComponents = [ pkgs.home-assistant-custom-components.<x> ... ]` for HACS-equivalents that already exist in nixpkgs (`pkgs/servers/home-assistant/custom-components/`).
- `services.home-assistant.customLovelaceModules = [ pkgs.home-assistant-custom-lovelace-modules.<x> ]` for frontend cards.
- Zigbee stick → ZHA component + udev rule pinning the CP210x to a stable `/dev/serial/by-id/...`.
- Add-on replacements:
  - Mosquitto → `services.mosquitto`
  - ESPHome → `services.esphome`
  - Studio Code Server → `services.code-server` (or skip; edit from this repo)
  - Node-RED → `services.node-red`
- Persistent state (`/var/lib/hass`) stays on the host, but is the **only** mutable surface — config files are all in the Nix store.

**Pros:** Fully reproducible, atomic rollback via `nixos-rebuild switch --rollback`, no qcow2, no Supervisor security surface, plugins reviewed in PRs.
**Cons:** No Add-on Store — every add-on must have a Nix equivalent or be packaged. Possible feature regressions for HACS-only integrations not yet in nixpkgs. Migration is a one-way door (statefulness: HA DB, Zigbee mesh keys).

### Option C — Containerised HA + git-tracked config-dir (hybrid, "servarr-style")

Splits the difference. HA runs as an OCI container under the existing `homelab.compose` framework (alongside the other stacks on `discovery`), and a separate repo (or subdir of this one) holds `/config`.

- New stack `home-assistant` under `/home/erik/servarr/machines/discovery/home-assistant/`:
  - `compose.yaml` runs `ghcr.io/home-assistant/home-assistant:stable` with `network_mode: host`, `--device=/dev/serial/by-id/usb-Silicon_Labs_CP2102N-...`.
  - `config/` bind-mount is a git submodule pointing at the private GitHub repo.
- Add-ons replaced by sibling containers in the same compose stack (Mosquitto, ESPHome, etc.) — they were going to be containers anyway under this model.
- CI: same GHA `ha core check_config` workflow against the config submodule.
- Deploy: a one-shot systemd unit (or `homelab.compose` reload) runs `git pull && docker compose restart homeassistant` after CI green.

**Pros:** Latest HA version always, no nixpkgs lag, fits the existing servarr mental model, easy declarative add-on equivalents (other containers). Config is plain YAML so HA UI edits still work; Nix-side change is minimal.
**Cons:** Slightly less "Nix-native" than Option B. Still no Supervisor UI (but that's a feature, not a bug, for our use case).

---

## 5. Decision

**Implemented → Option A.** Version control, validation, rollback, and PR-driven
configuration shipped without replacing the working appliance.

**Deferred → Option C.** A future container migration would belong to the `servarr`
household-workload repository, while this flake would own required host support.
Clean YAML reduces config migration cost, but HA state, Supervisor add-ons,
USB/Zigbee, backup, and rollback still make this a significant migration.

**Deferred → Option B.** Pure Nix remains an alternative only if concrete runtime
needs justify Add-on/HACS compatibility work.

No migration is scheduled. Retain HAOS until measured operational pain creates a
reason to reopen this decision.

---

## 6. Implementation record and deferred alternatives

### Phase 1 — Git-sync the existing HAOS instance (implemented)

1. **Repo bootstrap**
   - Create private GitHub repo `ErikBPF/home-assistant-config`.
   - Inside HAOS (via Studio Code Server terminal):
     ```bash
     cd /config
     git init && git branch -m main
     git config user.name "erik" && git config user.email "erik@..."
     ```
   - Add deploy key (read/write), copy public key into GitHub repo settings.

2. **`.gitignore`** — at minimum:
   ```
   secrets.yaml
   .storage/
   .cloud/
   home-assistant_v2.db*
   *.log
   *.log.*
   deps/
   tts/
   ```

3. **Restructure `configuration.yaml`** to use folder-based `!include`s:
   ```yaml
   automation: !include_dir_merge_list automations/
   script:     !include_dir_merge_named scripts/
   sensor:     !include_dir_merge_list  sensors/
   homeassistant:
     packages: !include_dir_named packages/
   ```
   Move existing UI automations into per-domain files (`automations/lighting.yaml`, etc.).

4. **Initial commit + push** — full snapshot.

5. **GitHub Actions** — `.github/workflows/validate.yaml`:
   ```yaml
   name: Validate HA config
   on: [push, pull_request]
   jobs:
     check:
       runs-on: ubuntu-latest
       steps:
         - uses: actions/checkout@v4
         - uses: frenck/action-home-assistant@v1
           with:
             path: "."
             secrets: ./tests/fake_secrets.yaml
             version: stable
   ```
   (`tests/fake_secrets.yaml` shadows `secrets.yaml` so CI can resolve `!secret` lookups.)

6. **Auto-commit of UI edits**
   - Shell command in `configuration.yaml`:
     ```yaml
     shell_command:
       backup_to_git: "bash /config/scripts/backup2git.sh"
     ```
   - `scripts/backup2git.sh`:
     ```bash
     #!/usr/bin/env bash
     set -e
     cd /config
     git add -A
     git diff --cached --quiet || git commit -m "ui: $(date -u +%Y-%m-%dT%H:%MZ) auto-snapshot"
     git push origin main
     ```
   - HA automation triggers daily at 02:00.

7. **Document plugins/HACS in repo** — vendor `custom_components/<name>/` into git directly (do **not** rely on HACS pulling them at runtime). Same for blueprints under `blueprints/automation/<author>/<name>.yaml`. From here on, "install a plugin" = open a PR.

### Deferred alternative — Migrate to containerised HA (Option C)

1. Add a household workload stack under the `servarr` repository for `discovery`.
2. In that stack:
   - `compose.yaml` with `ghcr.io/home-assistant/home-assistant:stable`, host networking, USB device passthrough by stable `by-id` path.
   - `config/` → git submodule of `home-assistant-config`.
   - Sibling services for replaced add-ons (`eclipse-mosquitto`, `esphome/esphome`).
3. **Migrate state**: full HAOS backup → restore into the container `/config` (HA's own restore handles DB, .storage, Zigbee mesh keys).
4. **Cut-over plan**: keep VM running, bring up container on a different MAC/IP, validate, then swap DHCP reservation and shut down the VM. Keep the qcow2 around for one release cycle.
5. Retire `modules/hosts/discovery/haos.nix` and `haos-domain.xml` (or gate them behind an `enable = false` toggle for one cycle).

### Deferred alternative — Nix-native

Skipped unless we hit concrete pain (e.g., container drift, add-on coupling). Tracked but not scheduled.

---

## 7. Reopening criteria

- A required integration cannot run reliably under HAOS.
- Supervisor or HAOS lifecycle creates recurring, measured operational failures.
- Existing backup and restore behavior proves insufficient.
- Container or NixOS migration offers a concrete capability unavailable in HAOS.

Before reopening, inventory add-ons and HACS components, test native backup restore,
export the Zigbee coordinator backup, choose runtime-secret handling under the D5
Vault/sops boundary, and define a tested rollback window.

---

## 8. Risks

| Risk | Mitigation |
|---|---|
| Leaking secrets to public repo | Private repo + strict `.gitignore` + sops-nix for `secrets.yaml` |
| Zigbee re-pair on container migration | Restore via HAOS backup file — preserves mesh keys |
| HACS plugin breakage when vendored | Pin commits in submodules / `pkgs.fetchFromGitHub` rev |
| GHA validation false-negative | Same `version: stable` track as production; pin when going to prod |
| Auto-commit loops (HA writes → push → pull → reload → HA writes) | Only commit non-`.storage` paths; never pull on the live instance unless CI is green |

---

## 9. HAOS → Container Regression Study

Concrete inventory of what disappears when we leave the HAOS VM behind (Option C / Option B). Use this checklist to decide whether each loss is acceptable before cutting over.

### 8.1 Lost: managed by Supervisor in HAOS

| HAOS feature | What it is | Container replacement | Cost |
|---|---|---|---|
| **Add-on Store (1-click installs)** | UI catalog of vetted containers (Mosquitto, ESPHome, Z2M, Node-RED, MariaDB, AdGuard, Studio Code Server, Samba, etc.) | Sibling compose services, declared in our compose stack | Each add-on needs a one-time port of its `config.yaml` + env vars to compose. Recurring cost: zero (still container, still YAML). |
| **One-click HA Core updates** | "Update available" banner → restart | `docker compose pull && up -d` (manual) or Watchtower / Renovate PR | Lose "click and done." Gain: pinned versions, rollback via image tag. |
| **Update notifications in UI** | Banner when new HA Core / add-on / OS available | RSS feed → HA `feedparser` integration, or Renovate / Dependabot on the compose file | DIY notifier needed; trivial but real work. |
| **Supervisor "backup/snapshot"** | Single UI button → tar of `/config` + add-on data + HA Core state | HA 2025.1+ **native backup engine** is now first-class and works in Container too | Mostly recovered — backups stay UI-driven, just minus add-on bundles. |
| **Add-on auto-restart on config change** | Supervisor watches add-on configs | `docker compose restart <svc>` (manual or by automation) | Minor friction. |
| **Network / DNS / SSL UI panels** | Supervisor UI for hostname, static IP, Let's Encrypt | NixOS host (`networking.*`, `security.acme`) — already declarative in this repo | Net win — moves out of UI, into Nix. |
| **Hassio / Supervisor APIs** | Endpoints under `/hassio/*` used by some integrations | **Absent** in Container | Hard regression — see §8.2. |
| **"Repairs" assistant** | Supervisor-aware health checks | Reduced; HA Core repairs panel still works for non-Supervisor issues | Minor. |
| **HACS install button "Reboot host"** | HACS can request OS-level restart | Not available; host is NixOS | Manual `systemctl restart` or compose restart. |

### 8.2 Integrations that depend on the Supervisor API

These integrations only function under HAOS / Supervised and **break** under Container:

- `hassio` (the integration itself)
- Add-on entities exposed via `hassio_*` (e.g., add-on update sensors)
- Some integrations probe `/hassio/info` for host metadata
- `update.home_assistant_*` entities for Supervisor / OS updates

**Mitigation:** none — these are intrinsic to HAOS. Audit `configuration.yaml` for `hassio` references during Phase 1; flag any UI dashboards that surface Supervisor entities.

### 8.3 Not lost (common misconceptions)

- **USB / Zigbee / Z-Wave passthrough** — works identically in compose (`devices:` block + udev `by-id` path). Already proven by `containers.nix` patterns in this repo.
- **HACS itself** — installs into `/config/custom_components/` regardless of install method. (We're vendoring into Git anyway — see Phase 1.7.)
- **ESPHome dashboard** — runs as its own container, no functional loss.
- **Voice (Assist / Whisper / Piper)** — official containers exist; same model as add-ons.
- **Frontend, automations, scripts, blueprints, dashboards** — pure HA Core, untouched.
- **Native backup engine (encrypted, scheduled, S3/WebDAV targets)** — present in Container since HA 2025.1.

### 8.4 Acceptance criteria before cutting over from HAOS

- [ ] Enumerated add-ons currently installed in production HAOS (run `ha addons list` via SSH add-on).
- [ ] Every add-on in that list has either: (a) a planned compose service, or (b) explicit decision to drop.
- [ ] No active integration in `configuration.yaml` references `hassio.*` services.
- [ ] HA-native backup configured + tested before VM shutdown.
- [ ] Zigbee `coordinator_backup.json` exported (NWK keys / PAN ID) — required to re-pair without re-onboarding every device.
- [ ] Rollback plan: keep `haos_ova-17.1.qcow2` for one full release cycle, gated behind `enable = false;` in `discovery-haos`.

### 8.5 Tactical recommendation

Going from HAOS → Container costs **add-ons + Supervisor UI conveniences**. It does **not** cost any HA Core capability, integrations, automations, or device support that we currently use (modulo the `hassio` integration audit). For a homelab where everything else is already containerized + declarative, the trade is favorable. The single biggest concrete risk is Zigbee re-pairing — mitigated by exporting the coordinator backup before cut-over.

---

## 10. Sync Direction & Conflict Model

Bidirectional sync (UI edits flow back to GitHub **and** GitHub PRs flow forward to HA) is the goal but also the failure mode. Concrete model:

### 9.1 Direction A — HA → GitHub (push, "capture UI edits")

Trigger: HA-side automation, daily at 02:00 + on demand via UI button.

Flow:
1. `scripts/backup2git.sh` runs `git add -A && git commit -m "ui: <ts>" && git push origin main` (or `git push origin ui-snapshot-<ts>` for safer PR review).
2. GHA validation runs on the resulting commit / PR.
3. Pre-existing protected `.gitignore` excludes `.storage/`, DB, secrets, logs.

Risks:
- UI edits could push broken YAML — GHA catches it post-hoc, not pre.
- Commits land directly on `main` if pushing to `main` — bypasses review.

Mitigation: push to a per-day branch (`ui-snapshot-2026-05-23`) and open a PR via `gh pr create` in the script; nothing lands on `main` without GHA green + manual merge.

### 9.2 Direction B — GitHub → HA (pull, "deploy PRs")

Trigger: GHA `workflow_run` on green CI, OR GitHub webhook → HA webhook automation.

Flow:
1. PR merged to `main` → GHA `validate.yaml` passes → workflow dispatches webhook to `https://ha.local/api/webhook/<token>`.
2. HA automation receives webhook → `shell_command.git_pull` runs `cd /config && git pull --ff-only`.
3. Automation calls `homeassistant.reload_all` (or restart, depending on what changed).

Risks:
- Webhook exposed publicly. Mitigation: `local_only: true` on the trigger + tailscale/VPN-only path, or a GHA self-hosted runner inside the LAN that does the pull via SSH.
- Pull happens while UI is mid-edit → un-committed UI changes get clobbered.
- `git pull --ff-only` fails if Direction A pushed first and trees diverged.

Mitigation: Direction A always pushes to a branch, never to `main`. Direction B only pulls `main`. `main` only moves via merged PR. **No commits ever happen directly on the live `/config` clone of `main`.**

### 9.3 The conflict question

If both directions are enabled naively, the loop is:
> UI edit → auto-commit to `main` → CI passes → pull on the live instance (no-op, already there) → UI edit again → ...

Safe enough *for non-overlapping files*. Breaks when the same file is touched by both a PR and a UI edit between snapshots.

**Recommended policy (Phase 1):**

| File class | Edit allowed via | Owned by |
|---|---|---|
| `configuration.yaml`, `packages/`, `custom_components/`, `blueprints/`, `*.nix` | **PR only** | Git |
| `automations.yaml`, `scripts.yaml`, `scenes.yaml`, `ui-lovelace.yaml` (UI-managed) | UI **or** PR, never both for the same entity | Either, last-write-wins per snapshot window |
| `.storage/`, DB, secrets | UI only (never in Git) | HAOS |

`restart_ignore` (à la official `git_pull` add-on) covers the UI-managed bucket — `git pull` doesn't restart HA when only those files changed, avoiding noisy reloads.

### 9.4 Phased sync rollout

| Phase | Direction A (HA → GH) | Direction B (GH → HA) | Notes |
|---|---|---|---|
| **1a** | ✅ daily auto-commit to `ui-snapshot-*` branch → PR | ❌ off | One-way snapshot; humans cherry-pick into `main`. Lowest risk. |
| **1b** | ✅ same | ✅ webhook → `git pull main` + reload, `local_only` | Bidirectional with policy above. |
| **2 (container)** | ✅ same | ✅ either webhook or `homeassistant/git_pull`-equivalent sidecar in compose | Same model, container-native. |

Start at 1a; promote to 1b only after a week with no surprises.

### 9.5 Acceptance criteria

- [ ] `.gitignore` audited — no `secrets.yaml` or `.storage/` ever pushed.
- [ ] Direction A pushes to non-`main` branch → PR.
- [ ] Direction B uses `--ff-only`; logs failures to a `persistent_notification`.
- [ ] Webhook endpoint not exposed to the public internet (Tailscale-only or LAN-only).
- [ ] `restart_ignore` covers UI-managed files so cosmetic pulls don't bounce HA.
- [ ] Disaster test: delete `/config`, re-clone from `main`, restore secrets from sops, restore `.storage/` from latest HA backup → instance returns to working state.

---

## 11. References

- [NixOS Wiki — Home Assistant](https://wiki.nixos.org/wiki/Home_Assistant)
- [nixpkgs `nixos/tests/home-assistant.nix`](https://github.com/NixOS/nixpkgs/blob/master/nixos/tests/home-assistant.nix) — canonical declarative example with blueprints + custom components
- [nixpkgs `pkgs/servers/home-assistant/custom-components`](https://github.com/NixOS/nixpkgs/tree/master/pkgs/servers/home-assistant/custom-components) — pre-packaged HACS-equivalents
- [Adding a custom_component in NixOS (Nathan Bijnens)](https://nathan.gs/2023/03/29/home-assistant-add-a-custom-component-in-nixos/)
- [Managing Home Assistant Config From GitHub (dfederm)](https://dfederm.com/managing-home-assistant-config-from-github/) — Phase-1-style workflow
- [HA Configuration Management with Git (newerest)](https://newerest.space/home-assistant-git-configuration-management/) — branching strategy & GHA validation
- [Automating Home Assistant Configuration to GitHub (Akbarsait)](https://akbarsait.com/blog/2024/07/22/automating-home-assistant-configuration-to-github/) — auto-commit cron pattern
- [Daily backup HA config into a git repository (gist)](https://gist.github.com/AkdM/70f3f600356b3b834ae0290bd6f741b3) — reference `backup2git.sh`
- [HAOS vs Docker vs VM comparison (al0pix)](https://al0pix.medium.com/home-assistant-installations-haos-vs-docker-vs-vm-compared-dfa86b0eb65e)
- [Migrating from HAOS to HA Container (bentasker)](https://www.bentasker.co.uk/posts/blog/general/migrating-from-homeassistant-os-to-homeassistant-in-docker.html) — Phase 2 reference
- [Home Assistant on NixOS with Docker (unix-experience.fr)](https://www.unix-experience.fr/en/home/home_assistant/) — container + Bluetooth/USB passthrough notes
- [Home Assistant blueprint docs](https://www.home-assistant.io/docs/automation/using_blueprints/)
- [Deprecating Core and Supervised installation methods (HA blog, 2025-05)](https://www.home-assistant.io/blog/2025/05/22/deprecating-core-and-supervised-installation-methods-and-32-bit-systems/) — only HAOS + Container survive
- [HA Supervised vs Container — feature delta (community)](https://community.home-assistant.io/t/ha-supervised-vs-ha-container-what-are-main-differences/419219)
- [HA OS vs Container vs Supervised 2026 (privacysmarthome)](https://www.privacysmarthome.com/guides/home-assistant-os-vs-container-vs-supervised-privacy-2026/)
- [Migrating from Supervisor to Docker — step-by-step (diyenjoying, 2025-06)](https://www.diyenjoying.com/2025/06/15/migrating-from-home-assistant-supervisor-to-docker-a-step-by-step-guide/)
- [Safeguarding HA Part 2 — backup overhaul in 2025.1 (jonahmay)](https://jonahmay.net/safeguarding-home-assistant-part-2/)
- [GitOps Home Assistant Configurations (Budiman JoJo)](https://budimanjojo.com/2021/11/04/gitops-home-assistant-configurations/) — webhook→pull→reload pattern
- [Official `git_pull` add-on docs](https://github.com/home-assistant/addons/blob/master/git_pull/DOCS.md) — `restart_ignore`, `repeat`, `auto_restart` options
- [PR #536: webhook trigger for `git_pull` add-on](https://github.com/home-assistant/addons/pull/536) — why webhook handling belongs in HA automations, not the add-on
- [git-ha-ppens — community native git integration](https://community.home-assistant.io/t/integration-to-sync-your-ha-configuration-with-a-private-git-repository/999148)
