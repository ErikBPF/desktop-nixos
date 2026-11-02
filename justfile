profile := "endeavour"

# Host IPs (LAN, SSH port 2222). Endeavour is Tailscale-only (roaming).
# Derived from the fleet SSOT (modules/meta.nix → fleet.json); regenerate with
# `just fleet-json` after changing an IP. archinaut is wifi (wlan0, DHCP-reserved
# on the wlan0 MAC; wired retired) — roaming/admin via Tailscale, deploy-rs via LAN.
ip_discovery := `jq -r '.hosts.discovery.ip' fleet.json`
ip_orion := `jq -r '.hosts.orion.ip' fleet.json`
ip_pathfinder := `jq -r '.hosts.pathfinder.ip' fleet.json`
ip_kepler := `jq -r '.hosts.kepler.ip' fleet.json`
ip_archinaut := `jq -r '.hosts.archinaut.ip' fleet.json`
ip_voyager := `jq -r '.hosts.voyager.ip' fleet.json`
ip_telstar := `jq -r '.hosts.telstar.ip' fleet.json`
ip_vanguard := `jq -r '.hosts.vanguard.ip' fleet.json`
ip_apollo := `jq -r '.hosts.apollo.ip' fleet.json`
tailscale_voyager := `jq -r '.hosts.voyager.tailscaleIp' fleet.json`
tailscale_vanguard := `jq -r '.hosts.vanguard.tailscaleIp' fleet.json`

# Export overrides so nested Just invocations retain the operator's builder pool.
export orion_builder := env_var_or_default("orion_builder", "ssh-ng://erik@orion-builder:2222 i686-linux,x86_64-linux,aarch64-linux /home/erik/.ssh/id_ed25519 16 2 big-parallel,benchmark,nixos-test")
export apollo_builder := env_var_or_default("apollo_builder", "ssh-ng://erik@apollo-builder:2222 i686-linux,x86_64-linux /home/erik/.ssh/id_ed25519 6 1 big-parallel,benchmark,kvm,nixos-test")

# Never ask a deployment target to build itself. Other x86_64 targets can use
# Orion as primary plus Apollo's deliberately constrained capacity.
_builders target:
    @if [ "{{target}}" = apollo ]; then \
        printf '%s\n' '{{orion_builder}}'; \
    elif [ "{{target}}" = orion ]; then \
        printf '%s\n' '{{apollo_builder}}'; \
    else \
        printf '%s ; %s\n' '{{orion_builder}}' '{{apollo_builder}}'; \
    fi

default:
    @just --list

# Resolve a host name to its LAN IP from the fleet SSOT (used by sync/kick recipes)
_host-ip target:
    #!/usr/bin/env bash
    set -euo pipefail
    ip="$(jq -r --arg h "{{target}}" '.hosts[$h].ip // empty' fleet.json)"
    if [ -z "$ip" ]; then echo "Unknown target or no IP: {{target}}" >&2; exit 1; fi
    echo "$ip"







# `switch`, `boot`, `upgrade` and `home-switch` run nixos-rebuild against THIS
# machine, so a foreign target installs that host's configuration here:
# `just switch apollo` on endeavour replaced SDDM/Hyprland with Apollo's server
# configuration, tore down the graphical session, and froze systemd. Remote
# targets deploy with `just deploy-rs <host>`. `build` and `dry` stay open for
# cross-host validation because they never activate anything.
_host-guard target:
    test "$(hostname)" = "{{target}}" || { echo "BLOCKED: {{target}} is not this host ($(hostname)); run it on {{target}}, or use 'just deploy-rs {{target}}'" >&2; exit 2; }


































# Endeavour is Tailscale only (roaming), use: just deploy endeavour <tailscale-ip> 2222


































































































# archinaut is aarch64: build on orion (binfmt qemu), substitute to the Pi.
# Bootstrap: build the SD image, dd it, first boot wired (see
# docs/proposals/2026-06-16-printer-nixos-host.md §9), then seed config.





# Push local servarr/ working tree to a host's /home/erik/servarr/ so that
# unpushed changes can be deployed without going through GitHub. The local
# symlink at `references/repos/servarr` points at ~/Documents/erik/servarr
# (alongside `references/repos/hermes-flake` and
# `references/repos/home-assistant-config`).
# Use these when you want to test compose changes before pushing main.

# Git is the single source→host path for servarr stacks. Each host's
# servarr-pull service does `git fetch + reset --hard origin/main` (see
# modules/server/orchestration.nix). rsync delivery was retired 2026-06-29: it
# dirtied the git tree and silently broke servarr-pull's old ff-only pull, so
# hosts stopped receiving commits. New flow:
#   1. edit references/repos/servarr/machines/<host>/...
#   2. just prep-servarr            # refresh generated mirrors (SOUL.md)
#   3. (in the servarr repo) git commit + push origin main
#   4. just pull-servarr <host>     # host fetches + resets to origin/main
#   5. just kick-stack <host> <stack>   # recreate containers whose files changed



































































































# Method by host class (see docs/proposals/2026-06-30-deploy-rs-as-deploy-standard.md):
#   • RAM-ample host (LAN server, A1 ARM) → `just provision <host> <user@ip[:port]>`
#     (nixos-anywhere; kexec works; disko partitions). Then deploy-rs for switches.
#   • 1 GB x86 Oracle micro (can't kexec) → `just infect-voyager` (nixos-infect).
#   • Raspberry Pi (archinaut) → SD image: `just build-archinaut-sd`, dd, first boot.

import 'just/fleet.just'

import 'just/deploy.just'

import 'just/secrets.just'

import 'just/discovery.just'

import 'just/kepler.just'

import 'just/kepler-recovery.just'

import 'just/orion.just'

import 'just/roaming.just'

import 'just/apollo.just'

import 'just/harbor.just'

import 'just/k3s.just'

import 'just/hermes.just'

import 'just/kindle.just'

import 'just/servarr.just'

import 'just/monitoring.just'
