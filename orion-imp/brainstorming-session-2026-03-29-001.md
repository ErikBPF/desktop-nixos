---
stepsCompleted: [1, 2, 3, 4]
inputDocuments: []
session_topic: 'Orion HTPC migration from Bazzite/Docker to NixOS'
session_goals: 'Define migration scope, research HTPC experience, nativize services, preserve AI serving, transparent to living room users'
selected_approach: 'ai-recommended'
techniques_used: ['morphological-analysis', 'role-playing', 'first-principles-thinking']
ideas_generated: 26
context_file: 'references/orion/'
session_active: false
workflow_completed: true
---

## Session Overview

**Topic:** Migrating Orion from Bazzite (Docker Compose) to NixOS — HTPC focused on Steam gaming with daytime AI model serving
**Goals:**
1. Define full migration scope (native NixOS vs Docker vs systemd)
2. Research best HTPC experiences on NixOS (Steam Big Picture, gamescope, auto-login, controllers)
3. Adapt Tailscale, Syncthing, telemetry to native NixOS modules
4. Keep AI model serving (llama.cpp with AMD Vulkan on RX 9070XT)
5. Make transition invisible to living room users (boot → couch-ready)

### Context Guidance

_Current Orion runs Bazzite (immutable Fedora) with Docker Compose stacks: ai-models (llama-chat Vulkan, llama-embed CPU), shared (Tailscale, Syncthing, Alloy telemetry, Scrutiny, Hawser), hermes-agent (autonomous AI agent). AMD RX 9070XT GPU. Existing NixOS fleet uses flake-parts + import-tree, with pathfinder (desktop/gaming), discovery (server), and laptop hosts as templates._

### Session Setup

_AI-Recommended technique sequence: Morphological Analysis → Role Playing → First Principles Thinking. Focused on systematic component mapping, UX stress-testing from multiple perspectives, and NixOS-native optimization._

## Technique Selection

**Approach:** AI-Recommended Techniques
**Analysis Context:** Orion HTPC migration with focus on console-like UX + AI serving + NixOS nativization

**Recommended Techniques:**

- **Morphological Analysis:** Map all Orion components across dimensions (native NixOS / Docker / systemd) to find optimal combinations
- **Role Playing:** Embody couch gamer, remote admin, guest user, and auto-upgrade system to stress-test UX
- **First Principles Thinking:** Strip Bazzite assumptions and rebuild from NixOS fundamentals for native wins

## Technique Execution Results

### Phase 1: Morphological Analysis — Component Decision Matrix

Systematically mapped 7 dimensions of Orion's system against implementation strategies.

| Dimension | Decision | Rationale |
|-----------|----------|-----------|
| **Display Session** | Jovian-NixOS (Steam Deck UI + gamescope + SDDM autologin) | Full SteamOS 3.x replica. "Switch to Desktop" → Hyprland. Actively maintained, AMD-first. |
| **GPU/Graphics** | Mesa RADV only — unified Vulkan stack | Outperforms AMDVLK on RDNA 4. Same driver for gaming + AI. No ROCm idle power bug. |
| **AI Model Serving** | Docker Compose via Podman (dockerCompat) | Keep existing `ai-models.yml` as-is. Zero migration effort for riskiest component. |
| **Tailscale** | Native NixOS module | Reuse existing fleet pattern from `modules/networking/tailscale.nix`. Client mode, sops authkey. |
| **Syncthing** | Native NixOS module — empty but ready | Device IDs configured, no shared folders. Ready for future Kepler sync. |
| **Telemetry** | Native Grafana Alloy — fleet-wide module | New `modules/services/alloy.nix` for all hosts. Ships to Loki/Mimir on Discovery via Tailscale IP. |
| **Remaining Services** | Split: Podman autoPrune (native), Sunshine (native), Scrutiny/Hawser/Hermes (compose) | Nativize simple services, containerize complex ones. |

### Phase 2: Role Playing — Stakeholder Stress Testing

**Persona 1: Couch Gamer**
- Boot → GRUB (silent) → SDDM autologin → gamescope → Steam Deck UI. ~30s to controller-ready.
- Controllers: Xbox via Bluetooth (xpadneo), generic wired/USB dongle (kernel HID). Covered by steam-devices + game-devices udev rules.
- Media playback: non-issue — handled by separate devices. Orion is pure gaming + AI.
- Game crash: Steam Deck UI catches, returns to game list. No desktop flashes.

**Persona 2: Remote Admin**
- SSH over Tailscale, standard NixOS operations.
- No AI stop/start needed — llama.cpp idle timeout unloads model from VRAM automatically.
- Sunshine always-on — negligible resources when idle, same timeout logic protects VRAM.
- Config deploys: `just deploy orion <ip>` or `nixos-rebuild switch --flake .#orion`. Atomic, rollbackable.

**Persona 3: Auto-Upgrade System (3am)**
- NixOS generations in GRUB — couch user can self-recover by picking previous generation.
- Container images updated via automated PRs (Renovate/Dependabot), not auto-pulled.
- Jovian-NixOS flake input: no blocking, but security audit required before adoption.

**Persona 4: Fleet Consistency**
- New layered profile architecture: `profile-interactive` (audio, bluetooth, fonts, theming) + compositor plugins.
- `plugin-hyprland` for pathfinder/laptop. `plugin-htpc` for Orion. Each owns its SDDM config.
- SDDM ownership moved from interactive base to each plugin — avoids mkForce conflicts.

### Phase 3: First Principles Thinking — NixOS-Native Wins

| Principle | Insight | Impact |
|-----------|---------|--------|
| **Config IS the system** | `nixos-anywhere orion <ip>` rebuilds from zero. Only manual state: `/opt/models` (future: Syncthing from Kepler). | Eliminates recovery runbooks. |
| **Generations = fearless upgrades** | 5+ GRUB generations. Bad Jovian/Mesa update? Arrow keys to previous. | Couch user self-recovers. |
| **Atomic composition** | Native services + Podman containers co-evaluated. Firewall, systemd, users resolved at build time. | Eliminates "forgot to open a port" class of bugs. |
| **Fleet is one repo** | Orion joins pathfinder/discovery/laptop. Alloy module = one PR, all hosts get telemetry. | Operational complexity drops. |
| **No snowflake hosts** | Same deployment, secrets, monitoring across all hosts. No more "except on Orion." | One runbook for fleet. |
| **Clear boundary** | NixOS flake = OS substrate. Homelab repo = workloads (compose files). | Two repos evolve independently. |

## Idea Organization and Prioritization

### All Ideas by Theme

**Theme 1: Display & Gaming Experience**

| # | Idea | Description |
|---|------|-------------|
| HTPC #1 | Jovian-NixOS as Display Session | Steam Deck UI, gamescope, SDDM autologin, "Switch to Desktop" → Hyprland |
| GPU #2 | Mesa RADV Only | Unified Vulkan stack — single driver for gaming + AI inference |
| CTRL #10 | Controller Support | xpadneo (Xbox BT) + steam-devices + game-devices udev rules |
| SUNSHINE #9 | Native Sunshine | `services.sunshine` with capSysAdmin for KMS/DRM capture from gamescope |
| SUNSHINE-ALWAYS #12 | Sunshine Always-On | Persistent user service, negligible idle resources |
| GENERATIONS #19 | GRUB Generation Safety Net | 5+ generations, couch user self-recovers from bad upgrades |

**Theme 2: AI & Container Workloads**

| # | Idea | Description |
|---|------|-------------|
| AI #3 | Docker Compose via Podman | Keep `ai-models.yml` + `hermes-agent.yml` as-is via Podman dockerCompat |
| PRUNE #8 | Podman Auto-Prune | `virtualisation.podman.autoPrune.enable = true` replaces docker-prune container |
| AI-LIFE #11 | Passive AI Lifecycle | Idle timeout unloads model from VRAM — no stop/start orchestration |
| UPGRADE #13 | Container Updates via Automated PRs | Renovate/Dependabot for image version bumps |
| MODELS #18 | Manual Model Path | `/opt/models` now. TODO: Syncthing from Kepler when productive |
| COMPOSE-SEPARATE #26 | Compose in Homelab Repo | NixOS = OS substrate, homelab repo = workloads. Clear boundary. |

**Theme 3: Native NixOS Services**

| # | Idea | Description |
|---|------|-------------|
| NET #4 | Native Tailscale | Reuse fleet module, client mode, sops authkey |
| SYNC #5 | Native Syncthing — Empty | Device IDs configured, no folders for now |
| TEL #7 | Native Grafana Alloy | Fleet-wide module for all hosts |
| SUNSHINE #9 | Native Sunshine | `services.sunshine` with KMS capture |

**Theme 4: Fleet Architecture**

| # | Idea | Description |
|---|------|-------------|
| PROFILE #15 | Interactive Base + Compositor Plugins | `profile-interactive` + `plugin-hyprland` / `plugin-htpc` |
| SDDM #16 | SDDM Owned by Plugin | Each compositor plugin controls its own display manager |
| ATOMIC #20 | Unified System Evaluation | All services co-evaluated at build time |
| FLEET-ALLOY #21 | Alloy Fleet Module | One PR enables telemetry across all hosts |
| ALLOY-ENDPOINT #22 | Alloy via Tailscale IPs | Stable endpoints, no DNS dependency |
| NO-SNOWFLAKE #24 | Uniform Fleet Operations | Same deploy, secrets, monitoring everywhere |

**Theme 5: Security & Operations**

| # | Idea | Description |
|---|------|-------------|
| JOVIAN-SEC #14 | Jovian Security Audit | Review repo before adding as flake input |
| REPRO #17 | Full Machine Reproducibility | `nixos-anywhere` rebuilds Orion from zero |
| TAILSCALE-ACL #23 | Tailscale ACL Policy Review | Least-privilege rules for fleet mesh |

### Implementation Priority

**Phase 0: Pre-Flight**
- [ ] Jovian-NixOS security audit (#14)
- [ ] Tailscale ACL policy review (#23)

**Phase 1: Quick Wins — Fleet & Profile Refactoring**
- [ ] Refactor `profile-desktop` into `profile-interactive` + `plugin-hyprland` (#15, #16)
- [ ] Create `plugin-htpc` module (Jovian + Sunshine + controllers + gamemode)
- [ ] Create `modules/services/alloy.nix` fleet-wide telemetry module (#7, #21, #22)

**Phase 2: Orion Host — Core HTPC**
- [ ] Create `modules/hosts/orion/` (default, hardware, networking, syncthing, ssh)
- [ ] Jovian-NixOS integration — Steam Deck UI + gamescope + SDDM autologin (#1)
- [ ] AMD RX 9070XT — RADV, early KMS, 32-bit graphics, firmware (#2)
- [ ] Sunshine — native service, KMS capture, firewall, uinput (#9, #12)
- [ ] Controllers — xpadneo, steam-devices, game-devices udev (#10)
- [ ] GRUB generations — silent boot, 5+ generations (#19)

**Phase 3: Orion Host — Services & Integration**
- [ ] Tailscale native — import existing module, client mode (#4)
- [ ] Syncthing native — device IDs, no folders (#5)
- [ ] Alloy native — ship to Discovery via Tailscale IP (#7)
- [ ] Podman — enable, dockerCompat, dockerSocket, autoPrune (#3, #8)
- [ ] Model path `/opt/models` with future Syncthing comment (#18)

**Phase 4: Deploy & Validate**
- [ ] `nixos-anywhere orion <ip>` — provision from bare metal (#17)
- [ ] Validate: Steam Deck UI boots, controllers work, Sunshine streams
- [ ] Validate: `docker compose up` works for AI stack from homelab repo
- [ ] Validate: Tailscale mesh, Alloy telemetry reaching Discovery
- [ ] Validate: GRUB rollback works from couch (no keyboard needed — controller?)

**Phase 5: Fleet Rollout**
- [ ] Deploy Alloy module to pathfinder, discovery, laptop (#21)
- [ ] Verify fleet-wide telemetry in Grafana
- [ ] Container image automated PRs setup (#13)

## Session Summary and Insights

**Key Achievements:**
- 26 architectural decisions covering every component of the Orion migration
- Clear native-vs-container boundary: NixOS owns the OS, homelab repo owns workloads
- New fleet-wide profile architecture that benefits all hosts, not just Orion
- Discovered Jovian-NixOS as the optimal HTPC framework (full SteamOS replica)
- Confirmed Vulkan-only GPU strategy avoids ROCm complexity entirely
- Identified passive AI lifecycle (idle timeout) eliminates scheduling complexity

**Key Research Findings:**
- Jovian-NixOS: mature, actively maintained, AMD-first, provides Steam Deck UI + gamescope + Decky Loader
- Mesa RADV outperforms AMDVLK on RX 9070 XT (RDNA 4)
- ROCm on RDNA 4 has idle power bug — Vulkan backend does not
- nixpkgs `services.sunshine` works with gamescope via KMS capture (capSysAdmin required)
- nixpkgs `services.llama-cpp` exists but container approach is safer for GPU workloads

**Breakthrough Moments:**
- Idle timeout eliminates the entire "day mode / night mode" orchestration
- Profile refactoring benefits the whole fleet — `profile-interactive` + compositor plugins
- GRUB generations give couch users a self-recovery mechanism without SSH/terminal

**Creative Facilitation Narrative:**
_Started with systematic component mapping (morphological analysis) to establish the decision space. Role playing from 4 perspectives caught UX blind spots — the couch gamer's media needs were a non-issue, and the remote admin's AI lifecycle was simpler than expected (idle timeout). First principles thinking revealed that NixOS's atomic composition and generation system are the biggest wins over Bazzite — fearless upgrades and full reproducibility. The session produced a clean migration definition with clear phases and a fleet architecture improvement that was not in the original scope._

## Research References

**HTPC / Gaming:**
- [Jovian-NixOS](https://github.com/Jovian-Experiments/Jovian-NixOS) — Steam Deck UI on NixOS
- [SteamNix](https://github.com/SteamNix/SteamNix) — SteamOS but Nix Flavoured
- [play.nix](https://github.com/TophC7/play.nix) — Gamescope Wayland flake
- [NixOS Wiki - Steam](https://wiki.nixos.org/wiki/Steam)
- [NixOS Wiki - AMD GPU](https://wiki.nixos.org/wiki/AMD_GPU)
- [NixOS Wiki - Kodi](https://wiki.nixos.org/wiki/Kodi)

**AI / GPU:**
- [NixOS Wiki - Ollama](https://wiki.nixos.org/wiki/Ollama)
- [ROCm RDNA 4 idle power bug](https://github.com/ROCm/ROCm/issues/5706)
- [Using ROCm with NixOS | lunnova.dev](https://lunnova.dev/articles/nixos-nixpkgs-rocm-usage/)
- [Phoronix - Mesa RADV vs AMDVLK on RX 9070](https://www.phoronix.com/review/radeon-rx9070-radv-amdvlk)

**Sunshine:**
- [NixOS Wiki - Sunshine](https://wiki.nixos.org/wiki/Sunshine)
- [Sunshine on NixOS (myme.no)](https://myme.no/posts/2025-12-11-hifi-sunshine-on-nixos.html)
- [Decky Sunshine Plugin](https://github.com/s0t7x/decky-sunshine)
