# Installation Guide

## Hosts

| Host | Type | Hardware | IP |
|------|------|----------|-----|
| pathfinder | Desktop | Intel i7 + Nvidia GTX, LUKS+btrfs | 192.168.10.125 |
| discovery | Server | Intel + Nvidia Quadro P2000, RAID1 SSD + HDD | 192.168.10.210 |
| laptop | Desktop | Intel i7-1165G7 + Iris Xe, NVMe LUKS+btrfs | DHCP |

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

All hosts pull from `main` on staggered crons:
- discovery: 03:30
- pathfinder: 05:00
- laptop: 05:30

No manual deploys needed after merging to main.

## Just Commands Reference

```
just                        # List all commands
just build [target]         # Build and switch locally
just boot [target]          # Build and set for next boot
just update                 # Update flake inputs
just lint                   # Run statix linter
just fmt                    # Format with alejandra
just fmt-check              # Check formatting
just check                  # Lint + fmt-check + dry-build all hosts
just deploy <t> <ip> [port] # Remote deploy via SSH
just nixos-anywhere ...     # Fresh remote install
just bootstrap <target>     # Fresh local install from ISO
just verify <t> <ip> [port] # Verify host health
just gc [days]              # Garbage collect nix store
just sops                   # Edit sops secrets
just age-private            # Generate age key from SSH key
just age-public             # Show age public key
just rsync-sops <ip> [port] # Copy sops key to remote host
just cache-keygen           # Generate nix cache signing key
```
