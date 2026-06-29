# Installation Guide

## Hosts

| Host       | Type    | Hardware                                     | IP             |
| ---------- | ------- | -------------------------------------------- | -------------- |
| pathfinder | Desktop | Intel i7 + Nvidia GTX 1080, LUKS+btrfs       | 192.168.10.125 |
| discovery  | Server  | Intel + Nvidia Quadro P2000, RAID1 SSD + HDD | 192.168.10.210 |
| laptop     | Laptop  | Intel i7-1165G7 + Iris Xe, NVMe LUKS+btrfs   | DHCP           |
| orion      | HTPC    | AMD Ryzen + RX 9070XT, Jovian Steam UI        | 192.168.10.220 |
| kepler     | NAS/AI  | AMD Ryzen 5 3600 + RTX 3070, ZFS pools        | 192.168.10.230 |
| archinaut  | Printer | RPi 3 Model B+ (BCM2837), BIQU B1 Klipper, WiFi | 192.168.10.225 |

`archinaut` is **services-only** (kernel-direct boot, no u-boot): NixOS owns the
OS + MCU-firmware build + package versions; all printer config lives in the
`klipper-biqu` sister repo, never in Nix. It is not provisioned by the
disko/nixos-anywhere flow below — see
[`../implemented/2026-06-20-archinaut-kernel-direct-boot.md`](../implemented/2026-06-20-archinaut-kernel-direct-boot.md).

## Prerequisites

- NixOS ISO (graphical, 25.11+) on USB for target machine
- This repo cloned on operator workstation
- Sops age key at `~/.config/sops/age/keys.txt` on operator workstation

### Providing the sops age key on a fresh install

The age key is needed for sops-nix to decrypt secrets (SSH keys, tailscale authkey). Three ways to provide it:

**Option A: Automatic (remote install)**
`just nixos-anywhere` copies the key from your workstation automatically. Nothing extra needed.

**Option B: USB stick (local install)**
1. Copy `~/.config/sops/age/keys.txt` to a USB drive
2. Boot the ISO, plug in the USB
3. When `just bootstrap` prompts for the age key path, enter the USB path (e.g., `/run/media/nixos/USB/keys.txt`)

**Option C: SCP from LAN (local install)**
1. Boot the ISO (it has SSH enabled, user `nixos`, password `1045`)
2. From your workstation: `scp ~/.config/sops/age/keys.txt nixos@<ip>:/tmp/age-keys.txt`
3. When `just bootstrap` prompts, enter `/tmp/age-keys.txt`

**Option D: Generate a new key (new machine, no existing key)**
1. Boot the ISO
2. `mkdir -p ~/.config/sops/age && nix run nixpkgs#age -- -keygen -o ~/.config/sops/age/keys.txt`
3. Add the public key to `.sops.yaml` in the repo and re-encrypt secrets
4. Use the generated key path when `just bootstrap` prompts

## Install Methods

### Remote install (from workstation)

Single command, fully automated after LUKS unlock:

```bash
just nixos-anywhere <target> <ip> <luks-pass> <iso-user>
# Example:
just nixos-anywhere pathfinder 192.168.10.125 mypassword nixos
```

**What happens:**
1. nixos-anywhere SSHes into the ISO, partitions disk (disko + LUKS), installs NixOS
2. Age key is staged automatically from your workstation
3. Machine reboots — enter LUKS password on console
4. First boot: activation scripts distribute the key, sops decrypts secrets, tailscale joins, home-manager activates
5. Machine is fully operational and in the fleet

### Local install (from NixOS ISO)

For when you're physically at the machine:

```bash
git clone https://github.com/ErikBPF/desktop-nixos.git
cd desktop-nixos
just bootstrap <target>
# Example:
just bootstrap laptop
```

**What happens:**
1. Prompts for LUKS password
2. Partitions disk with disko, installs NixOS
3. Prompts for age key path (see options above)
4. Reboot, enter LUKS password
5. Same first-boot flow as remote install

## Post-Install

### Verification

```bash
just verify <target> <ip> <ssh-port>
# Example:
just verify pathfinder 192.168.10.125 2222
```

Checks: failed units, tailscale status, syncthing, home-manager, sops key presence.

### Deploy changes

```bash
just deploy <target> <ip> <port>
# Example:
just deploy pathfinder 192.168.10.125 2222
```

### Fleet auto-update

Orion builds and caches all host closures at 03:00. All hosts (including orion)
update at 05:00 once the cache is warm. Every fleet host — pathfinder,
discovery, laptop, orion, kepler, **archinaut** — has `system.autoUpgrade`
enabled.

- orion `nix-cache-builder`: 03:00
- all hosts: 05:00

No manual deploys needed after merging to main.

> **kepler generation cap:** kepler's ESP is 512 MB and holds ~2 generations
> (`configurationLimit = 2` in `modules/hosts/kepler/default.nix`). More
> overflows `/boot` and breaks activation. Don't raise it without a bigger ESP.

## Orion (HTPC — Jovian Steam UI)

Orion is provisioned via nixos-anywhere. It boots directly into the Steam Deck UI (Jovian-NixOS).

```bash
just deploy-orion   # fresh install from NixOS ISO
just switch-orion   # deploy changes to running system
```

**Storage:** 3-disk layout — NVMe (OS), SSD1 (`/opt/models`), SSD2 (`/scratch`). No LUKS.

**Post-install notes:**
- Sunshine remote-play: pair via `http://orion:47990` from a client on the LAN
- AI inference: `llama.cpp` with Vulkan backend on the RX 9070XT
- Syncthing peers: discovery + kepler (models folder)

## Kepler (NAS / AI workstation)

Kepler is provisioned via nixos-anywhere. ZFS pools are **not** created by disko — they are created manually after first boot (see [`../reference/kepler-zfs-setup.md`](../reference/kepler-zfs-setup.md)).

```bash
just deploy-kepler   # fresh install from NixOS ISO (boots to 192.168.10.230)
just switch-kepler   # deploy changes to running system
```

**Storage:**
- OS: 238GB Toshiba M.2 SATA (`sde`) — btrfs, managed by disko
- `fast-pool`: RAIDZ1, 4× Kingston 480GB SSD (`sda/sdb/sdc/sdd`) → `/fast` (~1.4TB)
- `bulk-pool`: RAIDZ1, 5× Seagate 4TB HDD via LSI SAS3008 HBA → `/bulk` (~15TB) + 2× Kingston 120GB SSD as L2ARC cache

**HBA:** LSI SAS3008 confirmed IT mode (`Protocol=(Initiator,Target)`). Drives appear as `sdg–sdk` (HDDs) and `sdl/sdm` (cache SSDs).

**Post-install — ZFS pool creation:**
```bash
# After nixos-anywhere completes and host has booted:
ssh -p 2222 erik@192.168.10.230
# Follow ../reference/kepler-zfs-setup.md
```

**Post-install — Samba password:**
```bash
ssh -p 2222 erik@192.168.10.230 'sudo smbpasswd -a erik'
```

**Post-install — Syncthing device ID:**
```bash
# Get the ID and update modules/secrets.nix
ssh -p 2222 erik@192.168.10.230 'syncthing show -deviceid'
# Replace PLACEHOLDER in modules/secrets.nix with the real ID, then redeploy
```

**NFS mounts:** All fleet hosts mount `/mnt/nfs/{fast,bulk}` via Tailscale (`kepler` MagicDNS). Automount on first access, nofail.

**hostId:** `cf7e11b5` (from `/etc/machine-id` on live ISO)

## Just Commands Reference

`just` (no args) lists every recipe — it is the authority; the list below is
just the common ones and will drift, so trust `just` when they disagree.

```
# Local
just build [target]          # Build and switch locally
just boot [target]           # Build and set for next boot
just check                   # docs-check + lint + fmt-check + dry-build all hosts
just docs-check              # Verify in-repo doc links resolve
just dry <target>            # Dry-build one host
just gc [days]               # Garbage collect nix store

# Remote deploy (per host; laptop roams — use `just deploy laptop <ts-ip> 2222`)
just deploy <t> <ip> [port]  # Generic remote deploy via SSH
just switch-pathfinder       # Deploy changes to a running host
just switch-discovery / switch-orion / switch-kepler / switch-archinaut
just switch-all              # Deploy to the whole fleet
just verify <t> <ip> [port]  # Verify host health

# Fresh install
just nixos-anywhere ...      # Fresh remote install
just bootstrap <target>      # Fresh local install from ISO
just deploy-orion / deploy-kepler / deploy-discovery   # per-host fresh install
just build-archinaut-sd / seed-archinaut               # RPi printer host bring-up

# Sister repos
just prep-servarr            # refresh generated mirrors before committing servarr
just pull-servarr <host> [branch]   # host resets servarr clone to origin/<branch> (default main)
just kick-stack <host> <s>   # recreate a stack on the host after a pull
just sync-hermes-skills      # push hermes skills (separate non-git path)

# Secrets / cache
just sops                    # Edit sops secrets
just age-private / age-public        # age key from SSH key / show public key
just rsync-sops <ip> [port]  # Copy sops key to a remote host
just cache-keygen            # Generate nix cache signing key
```

## Working in this repo

The authoritative rules — never-commit patterns, commit hygiene, remote-deploy
policy — live in [`../../CLAUDE.md`](../../CLAUDE.md). Read it before committing
or deploying. A few install-time specifics:

- **Secrets are sops-encrypted only.** No plaintext credentials ever land in the
  repo. Edit with `just sops`; push the age key to a host with `just rsync-sops`.
  `secrets/*.yaml` must carry a `sops:` block before staging.
- **New files must be `git add`ed before any `nix` command sees them** — flake
  eval ignores untracked files (the error is a misleading "attribute missing").
- **Local junk is gitignored and safe to delete** — it regenerates on demand:
  `.direnv/`, `.ruff_cache/`, `result`/`result-*` symlinks, and agent runtime
  state (`.ralph/`, `.bg-shell/`, `_bmad-output/`, `logs/`).
- **`ampagent-*.deb` at the repo root is local-only and token-bearing** — the
  source `just add-ampagent` imports into the nix store. Never commit it; don't
  delete the only copy unless it is already in the store.
