---
stepsCompleted: [1, 2, 3, 4]
inputDocuments:
  - _bmad-output/brainstorming/brainstorming-session-2026-03-29-001.md
---

# Orion HTPC Migration - Epic Breakdown

## Overview

This document provides the complete epic and story breakdown for migrating Orion from Bazzite (Docker Compose) to NixOS, decomposing the requirements from the brainstorming session into implementable stories.

## Requirements Inventory

### Functional Requirements

FR1: Orion must boot directly into Steam Deck UI via Jovian-NixOS (gamescope + SDDM autologin) — no login screen, no typing
FR2: "Switch to Desktop" in Steam UI must transition to Hyprland session
FR3: AMD RX 9070XT must use Mesa RADV (Vulkan) with early KMS via `amdgpu` in initrd
FR4: Sunshine must stream games via KMS/DRM capture to Moonlight clients, always-on
FR5: Xbox Bluetooth, generic wired, and USB dongle controllers must work out of the box
FR6: Existing Docker Compose files (`ai-models.yml`, `hermes-agent.yml`) must run via Podman with dockerCompat
FR7: Tailscale must be native NixOS module (client mode, sops-managed authkey)
FR8: Syncthing must be native NixOS module with device IDs configured, no shared folders initially
FR9: Grafana Alloy must be a fleet-wide NixOS module shipping to Discovery's Loki/Mimir via Tailscale IP
FR10: `profile-desktop` must be refactored into `profile-interactive` (base) + compositor plugins (`plugin-hyprland`, `plugin-htpc`)
FR11: Each compositor plugin must own its SDDM configuration entirely
FR12: GRUB must retain 5+ generations for rollback by non-technical users

### NonFunctional Requirements

NFR1: Boot to controller-ready must be under 60 seconds
NFR2: AI model idle timeout handles VRAM contention — no manual stop/start orchestration needed
NFR3: Full machine reproducibility — `nixos-anywhere orion <ip>` must rebuild from zero
NFR4: NixOS flake = OS substrate, homelab repo = workloads — clear separation of concerns
NFR5: Orion must use same deployment patterns as fleet (just deploy, sops-nix, nixos-anywhere)
NFR6: Alloy module must be portable — any host imports it and gets telemetry

### Additional Requirements

- Jovian-NixOS flake input must pass security review before adoption
- Tailscale ACLs must be reviewed for least-privilege fleet access
- `/opt/models` remains manual path; comment for future Syncthing from Kepler
- Container image updates handled via automated PRs (Renovate/Dependabot) in homelab repo
- `virtualisation.podman.autoPrune.enable = true` replaces docker-prune container
- Sunshine requires udev workaround for NixOS 25.11+ (`input` group + manual udev rule)
- Podman with `dockerCompat = true` is the fleet standard — no `dockerSocket.enable`, shell aliases for `docker` → `podman`
- Tailscale ACLs must include TCP 80, 443 for all hosts (web services)

### UX Design Requirements

N/A — infrastructure project, no UI beyond Steam Deck UI (managed by Jovian).

### FR Coverage Map

| FR | Epic | Story | Description |
|----|------|-------|-------------|
| FR1 | Epic 2 | 2.2, 2.4 | Boot to Steam Deck UI via Jovian-NixOS |
| FR2 | Epic 2 | 2.2 | "Switch to Desktop" transitions to Hyprland |
| FR3 | Epic 2 | 2.2 | AMD RX 9070XT RADV + early KMS |
| FR4 | Epic 2 | 2.3, 2.4 | Sunshine always-on game streaming |
| FR5 | Epic 2 | 2.3, 2.4 | Controller support (Xbox BT, generic wired/dongle) |
| FR6 | Epic 3 | 3.2, 3.3 | Docker Compose via Podman dockerCompat |
| FR7 | Epic 3 | 3.1, 3.3 | Native Tailscale client mode |
| FR8 | Epic 3 | 3.1, 3.3 | Native Syncthing with no folders |
| FR9 | Epic 4 | 4.1, 4.3 | Fleet-wide Alloy telemetry module |
| FR10 | Epic 1 | 1.1, 1.3 | Profile refactoring (interactive + plugins) |
| FR11 | Epic 1 | 1.1, 1.2, 1.3 | SDDM owned by compositor plugin |
| FR12 | Epic 2 | 2.2, 2.4 | GRUB 5+ generations for rollback |

## Epic List

**Implementation order: Epic 1 → Epic 2 → Epic 3 → Epic 4**
(Epic 4 can run in parallel with Epics 2/3 since it's fleet-wide and independent.)

### Epic 1: Fleet Profile Architecture
Fleet maintainer can manage desktop and HTPC hosts from a shared interactive base with compositor-specific plugins, eliminating duplicated config.
**FRs covered:** FR10, FR11

### Epic 2: Orion Console Gaming Experience
Couch gamer powers on Orion and is in the Steam Deck UI with controller in hand in under 60 seconds. Can stream games remotely via Moonlight from anywhere in the house.
**FRs covered:** FR1, FR2, FR3, FR4, FR5, FR12

### Epic 3: Orion Remote Services & AI
Remote admin SSHes into Orion over Tailscale, AI models serve requests via Podman, Syncthing is ready for future sync. Machine uses same fleet patterns as all other hosts.
**FRs covered:** FR6, FR7, FR8

### Epic 4: Fleet Observability & Security
Operator opens Grafana and sees logs/metrics from every NixOS host, with least-privilege Tailscale ACLs governing fleet access.
**FRs covered:** FR9

---

## Epic 1: Fleet Profile Architecture

Fleet maintainer can manage desktop and HTPC hosts from a shared interactive base with compositor-specific plugins, eliminating duplicated config.

### Story 1.1: Extract Profile-Interactive and Plugin-Hyprland from Profile-Desktop

As a **fleet maintainer**,
I want the desktop profile split into a compositor-agnostic base (`profile-interactive`) and a Hyprland-specific plugin (`plugin-hyprland`),
So that hosts with different display experiences share common audio, bluetooth, fonts, and theming without pulling in Hyprland.

**Acceptance Criteria:**

**Given** `profile-interactive` exists at `modules/profiles/interactive.nix`
**When** it is imported by a host configuration
**Then** it provides: audio (Pipewire), bluetooth, fonts, xdg-portal base, theming, peripherals
**And** it does NOT include any Hyprland, SDDM, or compositor-specific configuration

**Given** `plugin-hyprland` exists at `modules/profiles/plugin-hyprland.nix`
**When** it is imported alongside `profile-interactive`
**Then** it provides: Hyprland compositor, SDDM with Hyprland session, hyprland-specific packages (quickshell, hyprshot, swww), and home-manager modules (hypridle, hyprlock, mako, rofi, wlogout)

**Given** pathfinder's `default.nix` imports `profile-interactive` + `plugin-hyprland` instead of `profile-desktop`
**When** `nix eval .#nixosConfigurations.pathfinder.config.system.build.toplevel.drvPath` is run
**Then** it succeeds without errors

**Given** laptop's `default.nix` imports `profile-interactive` + `plugin-hyprland`
**When** `nix eval .#nixosConfigurations.laptop.config.system.build.toplevel.drvPath` is run
**Then** it succeeds without errors

**Given** all hosts are updated
**When** `nix develop -c just check` is run
**Then** lint, format check, and dry-build pass with no new warnings

### Story 1.2: Create Plugin-HTPC Skeleton

As a **fleet maintainer**,
I want a `plugin-htpc` module that provides Jovian-NixOS Steam Deck UI, Sunshine, controllers, and gamemode,
So that HTPC hosts get a console-like experience by importing one plugin.

**Acceptance Criteria:**

**Given** `plugin-htpc` exists at `modules/profiles/plugin-htpc.nix`
**When** it is imported alongside `profile-interactive`
**Then** it provides: Jovian-NixOS Steam session (gamescope + SDDM autologin), Sunshine game streaming with capSysAdmin for KMS capture, gamemode, controller udev rules (steam-devices, game-devices, xpadneo), proton-ge-bin
**And** SDDM is configured by plugin-htpc with autologin + gamescope-wayland session

**Given** `plugin-htpc` is imported without `plugin-hyprland`
**When** the NixOS configuration is evaluated
**Then** no Hyprland-related packages or config appear in the system closure

**Given** Jovian-NixOS flake input is added to `flake.nix`
**When** `nix flake check` is run
**Then** it succeeds (Jovian input resolves and is compatible with nixpkgs-unstable)

### Story 1.3: Validate Fleet Builds After Profile Refactor

As a **fleet maintainer**,
I want to verify that all existing hosts still build and that the new plugin system works correctly,
So that the refactoring has not broken any host configuration.

**Acceptance Criteria:**

**Given** Stories 1.1 and 1.2 are complete
**When** `nix build .#nixosConfigurations.pathfinder.config.system.build.toplevel` is run
**Then** it succeeds

**Given** the build commands complete
**When** `nix build .#nixosConfigurations.laptop.config.system.build.toplevel` is run
**Then** it succeeds

**Given** the build commands complete
**When** `nix build .#nixosConfigurations.discovery.config.system.build.toplevel` is run
**Then** it succeeds

**Given** a test configuration importing `profile-interactive` + `plugin-htpc` is evaluated
**When** `nix eval` runs against it
**Then** it succeeds and the closure includes Jovian, Sunshine, and gamemode packages

### Story 1.4: Add Host README Documentation

As a **fleet maintainer**,
I want each host directory to contain a README describing its purpose, hardware, use case, and quick commands,
So that any operator can understand the fleet at a glance without reading NixOS configs.

**Acceptance Criteria:**

**Given** `modules/hosts/pathfinder/README.md` exists
**When** an operator reads it
**Then** it contains: purpose (desktop/gaming workstation), hardware (CPU, GPU, storage), use case (daily driver with Hyprland), and quick commands (`just build pathfinder`, `just deploy pathfinder <ip>`)

**Given** `modules/hosts/discovery/README.md` exists
**When** an operator reads it
**Then** it contains: purpose (server/infrastructure), hardware (CPU, GPU, storage), use case (nix cache, reverse proxy, monitoring, Tailscale subnet router), and quick commands

**Given** `modules/hosts/laptop/README.md` exists
**When** an operator reads it
**Then** it contains: purpose (mobile workstation), hardware (CPU, GPU, storage), use case (portable Hyprland desktop), and quick commands

**Given** a new host is added to the fleet (e.g., Orion in Epic 2)
**When** the developer follows the pattern
**Then** a README is created as part of the host directory with the same structure

---

## Epic 2: Orion Console Gaming Experience

Couch gamer powers on Orion and is in the Steam Deck UI with controller in hand in under 60 seconds. Can stream games remotely via Moonlight from anywhere in the house.

### Story 2.1: Jovian-NixOS Security Audit

As a **fleet maintainer**,
I want to verify that the Jovian-NixOS repository is safe to add as a flake input,
So that I don't introduce supply chain risk to machines running with root privileges.

**Acceptance Criteria:**

**Given** the Jovian-NixOS repository at `github:Jovian-Experiments/Jovian-NixOS`
**When** the audit reviews contributor history, commit signing, CI/CD pipeline, and overlay scope
**Then** a written assessment documents: number of maintainers, signing practices, what nixpkgs packages are patched/overlaid, scope of NixOS module permissions, and any red flags

**Given** the audit is complete
**When** the assessment is reviewed by the operator
**Then** a clear **GO** or **NO-GO** decision is recorded
**And** if NO-GO, an alternative approach is documented (fallback to nixpkgs `gamescopeSession` + SDDM autologin)

**Given** the decision is GO
**When** the Jovian flake input is added to `flake.nix`
**Then** `inputs.jovian.inputs.nixpkgs.follows = "nixpkgs"` pins Jovian to our nixpkgs version

### Story 2.2: Create Orion Host with Jovian-NixOS and AMD GPU

As a **couch gamer**,
I want Orion to boot directly into the Steam Deck UI with full AMD GPU acceleration,
So that I get a console-like experience without seeing a login screen or desktop.

**Acceptance Criteria:**

**Given** `modules/hosts/orion/default.nix` exists
**When** it imports `profile-base`, `profile-interactive`, `plugin-htpc`, and Orion-specific hardware/networking/syncthing modules
**Then** `nix eval .#nixosConfigurations.orion.config.system.build.toplevel.drvPath` succeeds

**Given** Orion's hardware module configures AMD RX 9070XT
**When** the system boots
**Then** `amdgpu` is loaded in initrd (early KMS), `hardware.graphics.enable = true` and `enable32Bit = true` are set, and `jovian.hardware.has.amd.gpu = true` is configured

**Given** Jovian-NixOS is configured with `jovian.steam.autoStart = true` and `jovian.steam.user = "erik"`
**When** Orion boots
**Then** SDDM autologins to the gamescope-wayland session displaying the Steam Deck UI

**Given** `jovian.steam.desktopSession = "hyprland"` is configured
**When** the user selects "Switch to Desktop" in the Steam Deck UI
**Then** the session transitions to Hyprland

**Given** boot parameters include `quiet splash` and `boot.consoleLogLevel = 0`
**When** Orion boots
**Then** no kernel text or systemd output is visible — clean transition from BIOS to Steam UI

**Given** GRUB is configured to retain 5+ generations
**When** a previous generation is selected from the GRUB boot menu
**Then** the system boots into that generation's working configuration

**Given** `modules/hosts/orion/README.md` exists
**When** an operator reads it
**Then** it contains: purpose (HTPC/gaming + daytime AI), hardware (AMD RX 9070XT, CPU, storage), use case (console-like Steam Deck UI, remote AI inference), and quick commands

### Story 2.3: Configure Sunshine and Controller Support

As a **remote gamer**,
I want to stream games from Orion to any Moonlight client on my network, and use Xbox/generic controllers on the couch,
So that I can game from any room and with any controller I pick up.

**Acceptance Criteria:**

**Given** `services.sunshine` is enabled with `capSysAdmin = true` and `openFirewall = true`
**When** the system is running
**Then** Sunshine is accessible for Moonlight pairing on TCP 47989 and streaming on UDP 47998-48000

**Given** Sunshine uses KMS/DRM capture
**When** a Moonlight client connects while gamescope is the active compositor
**Then** the game stream is captured from the gamescope framebuffer with HDR support if the display supports it

**Given** the user is in the `input` group and udev rules for `/dev/uinput` are configured
**When** a Moonlight client sends controller input
**Then** input is passed through to the game running on Orion

**Given** `hardware.xpadneo.enable = true` is configured
**When** an Xbox controller is paired via Bluetooth
**Then** it is recognized by Steam and usable in games

**Given** `services.udev.packages` includes `game-devices-udev-rules` and `steam-devices-udev-rules` (via `programs.steam.enable`)
**When** a generic wired or USB dongle controller is connected
**Then** it is recognized by Steam without additional configuration

### Story 2.4: Validate Orion HTPC Experience

As a **couch gamer**,
I want to verify the complete boot-to-gaming and remote streaming experience works end-to-end,
So that the HTPC migration delivers a console-like experience.

**Acceptance Criteria:**

**Given** Orion is provisioned and booted
**When** power is pressed
**Then** the Steam Deck UI is displayed within 60 seconds (NFR1), verified via `systemd-analyze` + visual confirmation

**Given** the Steam Deck UI is active
**When** an Xbox Bluetooth controller is used to navigate
**Then** the UI responds to controller input without configuration

**Given** a game is launched from the Steam UI
**When** it runs via Proton or native
**Then** gamescope handles resolution scaling and the game renders with RADV Vulkan

**Given** the game is exited or crashes
**When** control returns to the Steam Deck UI
**Then** no desktop or terminal is visible — the UI catches the exit cleanly

**Given** Sunshine is running
**When** a Moonlight client on the LAN connects and pairs
**Then** the game stream is displayed on the client with controller input working

**Given** GRUB has 5+ generations
**When** a bad NixOS update breaks the Steam session
**Then** the user can reboot, select a previous generation from GRUB, and return to a working Steam UI

---

## Epic 3: Orion Remote Services & AI

Remote admin SSHes into Orion over Tailscale, AI models serve requests via Podman, Syncthing is ready for future sync. Machine uses same fleet patterns as all other hosts.

### Story 3.1: Configure Native Tailscale and Syncthing

As a **remote admin**,
I want Orion on the Tailscale mesh with native NixOS modules and Syncthing ready for future use,
So that I can SSH into Orion from anywhere and the machine participates in the fleet mesh.

**Acceptance Criteria:**

**Given** Orion's networking module imports the existing `modules/networking/tailscale.nix`
**When** the system activates
**Then** Tailscale connects in client mode using the sops-managed `tailscale_authkey`
**And** `tailscale status --peers=false` shows the host connected with hostname `orion`

**Given** Orion's networking module configures firewall rules
**When** the configuration is evaluated
**Then** TCP 22000 (Syncthing) and UDP 21027 (Syncthing discovery) are open
**And** SSH is accessible on port 2222 (from `profile-base`)

**Given** Orion's syncthing module configures device IDs from `config.syncthingDeviceIDs`
**When** the Syncthing service starts
**Then** devices (discovery, kepler) are configured as peers
**And** no shared folders are defined
**And** GUI is accessible at `127.0.0.1:8384`

**Given** the Syncthing configuration
**When** an operator reviews the module
**Then** a comment documents: `# TODO: Add shared folders when Kepler is on NixOS (sync /opt/models from fast/models)`

### Story 3.2: Configure Podman Runtime for AI Workloads

As a **remote admin**,
I want Podman running on Orion with Docker Compose compatibility and GPU access,
So that the existing AI model compose files run unmodified from the homelab repo.

**Acceptance Criteria:**

**Given** `virtualisation.podman` is enabled with `dockerCompat = true`
**When** the operator runs `docker --version` on Orion
**Then** Podman responds as a Docker-compatible runtime
**And** `dockerSocket.enable` is NOT set (pure Podman, no compatibility socket)

**Given** `docker-compose` is in `environment.systemPackages`
**When** the operator runs `docker compose` from the homelab repo's Orion directory
**Then** compose commands execute against the Podman backend without sudo

**Given** shell aliases are configured in fish/bash for the fleet
**When** the operator types `docker` in a shell
**Then** it resolves to `podman` via `dockerCompat`
**And** a comment documents this as the fleet standard for future host migrations

**Given** `virtualisation.podman.autoPrune.enable = true` is configured
**When** the auto-prune timer fires
**Then** dangling images and unused containers are cleaned up without manual intervention

**Given** `/dev/dri` and `/dev/kfd` exist on the host (AMD GPU devices)
**When** a compose service specifies `--device=/dev/dri:/dev/dri`
**Then** the container has Vulkan GPU access for llama.cpp inference

**Given** `/opt/models` exists on the host with GGUF model files
**When** a compose service mounts `/opt/models:/opt/models`
**Then** the model files are accessible inside the container
**And** a comment in the hardware module documents: `# TODO: Replace with Syncthing from Kepler fast/models when Kepler is on NixOS`

### Story 3.3: Validate Remote Services and AI Stack

As a **remote admin**,
I want to verify that Tailscale, Syncthing, and the AI compose stack all work correctly on Orion,
So that the machine is fleet-ready and serving AI models.

**Acceptance Criteria:**

**Given** Orion is provisioned with Stories 3.1 and 3.2 complete
**When** `ssh -p 2222 erik@orion` is run from another Tailscale host
**Then** the SSH session connects successfully

**Given** the homelab repo's AI compose files are deployed to Orion
**When** `docker compose -f ai-models.yml up -d` is run
**Then** the llama-chat container starts with Vulkan GPU access
**And** `curl http://localhost:8503/health` returns healthy

**Given** the llama-chat model is loaded and serving
**When** no requests arrive for the configured idle timeout period
**Then** the model unloads from VRAM (NFR2)
**And** `radeontop` shows GPU clocks at idle

**Given** Syncthing is running with no shared folders
**When** the operator checks the Syncthing GUI at `127.0.0.1:8384`
**Then** peer devices are listed and reachable
**And** no folders are syncing

**Given** all services are validated
**When** `systemctl --failed --no-legend` is run
**Then** no failed units are listed

---

## Epic 4: Fleet Observability & Security

Operator opens Grafana and sees logs/metrics from every NixOS host, with least-privilege Tailscale ACLs governing fleet access.

### Story 4.1: Create Fleet-Wide Alloy Telemetry Module

As a **fleet operator**,
I want a shared Alloy NixOS module that any host can import to ship logs and metrics to Discovery,
So that adding observability to a host is a single import with no per-host configuration.

**Acceptance Criteria:**

**Given** `modules/services/alloy.nix` exists
**When** it is imported by a host configuration
**Then** Grafana Alloy runs as a systemd service shipping Docker/Podman logs to Loki and host/container metrics to Mimir on Discovery

**Given** the module accepts options for Loki and Mimir endpoints
**When** the default values use Discovery's Tailscale IP (e.g., `100.x.x.x`)
**Then** no per-host endpoint configuration is needed for the standard fleet setup
**And** endpoints are overridable for non-standard deployments

**Given** the module configures log discovery
**When** containers or systemd services produce logs
**Then** Alloy discovers and ships them with host and service labels

**Given** the module configures host metrics
**When** Alloy scrapes procfs/sysfs
**Then** CPU, memory, disk, and network metrics are shipped to Mimir with the host label set to `config.networking.hostName`

**Given** the module is imported by Orion
**When** `nix eval .#nixosConfigurations.orion.config.system.build.toplevel.drvPath` is run
**Then** it succeeds and the closure includes the Alloy package and configuration

**Given** the module is portable (NFR6)
**When** it is imported by any host (pathfinder, discovery, laptop, orion)
**Then** it works without host-specific modifications

### Story 4.2: Tailscale ACL Policy Review and Implementation

As a **fleet operator**,
I want Tailscale ACLs to enforce least-privilege access between fleet hosts and devices,
So that only intended traffic flows between machines on the mesh.

**Acceptance Criteria:**

**Given** the current Tailscale ACL policy is reviewed
**When** the operator audits the default-allow rules
**Then** a document lists all required access patterns:
- All hosts: SSH on port 2222
- All hosts: TCP 80, 443 (web services, reverse proxy)
- All hosts → Discovery: Loki (3100), Mimir (9009) for telemetry
- Kepler → Orion: LiteLLM health check on port 8503
- Personal devices → Orion: Sunshine ports (47984, 47989, 47990, 48010 TCP; 47998-48000, 48010 UDP)
- All hosts: Syncthing (22000 TCP, 21027 UDP)
- Discovery: subnet router for 192.168.10.0/24

**Given** the ACL document is approved by the operator
**When** the policy is applied via `tailscale acl` or the Tailscale admin console
**Then** only documented access patterns are permitted
**And** undocumented port access between hosts is denied

**Given** the ACL policy is applied
**When** Orion's Tailscale health check is tested from Kepler on port 8503
**Then** the connection succeeds

**Given** the ACL policy is applied
**When** an unauthorized port is tested between hosts (e.g., port 9999)
**Then** the connection is refused

### Story 4.3: Deploy Alloy to All Hosts and Validate Fleet Telemetry

As a **fleet operator**,
I want Alloy deployed to all NixOS hosts with verified data flowing to Grafana,
So that I have a single dashboard showing the health of the entire fleet.

**Acceptance Criteria:**

**Given** the Alloy module from Story 4.1 is imported in pathfinder's configuration
**When** `nix build .#nixosConfigurations.pathfinder.config.system.build.toplevel` is run
**Then** it succeeds and includes Alloy

**Given** the Alloy module is imported in discovery's configuration
**When** `nix build .#nixosConfigurations.discovery.config.system.build.toplevel` is run
**Then** it succeeds

**Given** the Alloy module is imported in laptop's configuration
**When** `nix build .#nixosConfigurations.laptop.config.system.build.toplevel` is run
**Then** it succeeds

**Given** Alloy is deployed and running on Orion
**When** the operator queries Loki on Discovery with `{host="orion"}`
**Then** logs from Orion's services are returned

**Given** Alloy is deployed to all 4 hosts
**When** the operator opens Grafana on Discovery
**Then** metrics from pathfinder, discovery, laptop, and orion are visible in Prometheus/Mimir datasource
**And** logs from all 4 hosts are visible in Loki datasource

**Given** one host's Alloy service is stopped
**When** the operator checks Grafana
**Then** that host's metrics stop arriving but other hosts continue shipping
**And** no cascading failures occur (NFR6 portability — each host is independent)
