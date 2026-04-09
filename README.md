# desktop-nixos

NixOS configuration for a 5-host homelab. Built on [flake-parts](https://flake.parts) +
[import-tree](https://github.com/vic/import-tree) following the
[dendritic](https://github.com/mightyiam/dendritic) pattern — every `.nix` file is a
top-level module, options replace `specialArgs`, no aggregator boilerplate.

## Hosts

| Host | Role | CPU | RAM | GPU | Storage | IP |
|------|------|-----|-----|-----|---------|-----|
| **pathfinder** | Desktop | i7-8750H | 32 GB | GTX 1060 Max-Q + UHD 630 (PRIME sync) | SATA · LUKS+btrfs | 192.168.10.125 |
| **laptop** | Laptop | Intel (mobile) | — | Intel Iris Xe | NVMe · LUKS+btrfs · FIDO2 | Tailscale (roaming) |
| **orion** | HTPC / Build server | Ryzen 9 5950X | 64 GB | Radeon RX 9070 XT | NVMe btrfs · 2×SSD ext4 | 192.168.10.220 |
| **discovery** | Home server | i5-4670 | 32 GB | Quadro P2000 | 2×SSD btrfs RAID1 · 3.6TB HDD | 192.168.10.210 |
| **kepler** | NAS / AI inference | Ryzen 5 3600 | 64 GB | RTX 3070 LHR | M.2 btrfs · ZFS RAIDZ1 | 192.168.10.230 |

SSH runs on **port 2222** fleet-wide.

## Stack

- **Window manager:** Hyprland + Quickshell bar + SDDM
- **Shell:** Fish + Starship + Atuin
- **Secrets:** sops-nix (age encryption)
- **Disk layout:** disko (LUKS+btrfs on desktops/laptop, RAID1 on discovery, ZFS on kepler)
- **Containers:** Docker / Podman + Compose (discovery, orion)
- **Monitoring:** Grafana Alloy
- **VPN:** Tailscale
- **Binary cache:** nix-serve on orion (LAN, port 5000)
- **Distributed builds:** laptop → orion (ssh-ng, 16 jobs)

## Layout

```
flake.nix                        # entry point: flake-parts + import-tree ./modules
modules/
  configurations.nix             # produces nixosConfigurations from configurations.nixos.*
  meta.nix                       # readOnly options: username, email, configPath
  systems.nix                    # supported systems
  hosts/
    pathfinder/                  # per-host: default.nix, hardware.nix, networking.nix, …
    orion/
    discovery/
    kepler/
    laptop/
  profiles/
    base.nix                     # all hosts: security, networking, services, packages
    desktop.nix                  # GUI hosts: Hyprland, fonts, audio, dev tools
    server.nix                   # headless hosts: orchestration
  security/                      # apparmor, audit, fail2ban, pam, sudo, …
  networking/                    # firewall, openssh, resolved, tailscale
  desktop/                       # hyprland, sddm, quickshell, rofi, …
  services/                      # sops, first-boot, distributed-builds, nix-cache, …
  shell/ terminal/ dev/ …
secrets/sops/secrets.yaml        # age-encrypted: passwords, SSH keys, Tailscale authkeys
config/                          # non-nix assets: QML, keyboard layouts, themes
```

## Day-to-day

```bash
just build             # nixos-rebuild switch on current host (offloads to orion)
just upgrade           # flake update + switch
just switch-orion      # remote deploy to orion
just switch-all        # parallel deploy to discovery + orion + pathfinder
just verify orion 192.168.10.220   # post-deploy health check
just dry               # dry-build current host
just check             # lint + fmt-check + dry-build all hosts
just lint              # statix
just fmt               # alejandra
just sops              # edit secrets/sops/secrets.yaml
```

## Bootstrapping a new host

### Remote (recommended) — nixos-anywhere

Boot the target from a NixOS ISO, then from any machine in the fleet:

```bash
# LUKS hosts (pathfinder, laptop)
just nixos-anywhere <host> <ip>

# Non-LUKS hosts (orion, discovery, kepler — dedicated scripts)
just deploy-orion
just deploy-discovery
just deploy-kepler
```

nixos-anywhere will: partition via disko, install NixOS, stage the age key for first-boot
sops decryption, and optionally generate `_hw-generated.nix`.

### Local — from NixOS ISO on the target itself

```bash
# Clone the repo onto the ISO environment, then:
just bootstrap <host>
```

Prompts for the LUKS password, partitions with disko, installs, and stages the age key.

## Secrets setup

Secrets are encrypted with [sops-nix](https://github.com/Mic92/sops-nix) using age keys
derived from SSH ed25519 keys.

```bash
# Derive your age private key from your SSH key
just age-private        # writes ~/.config/sops/age/keys.txt

# Print your age public key (add to .sops.yaml for a new machine)
just age-public

# Edit the secrets file
just sops
```

The `.sops.yaml` lists which age keys can decrypt `secrets/sops/secrets.yaml`. Add a new
host's key before provisioning it so sops-nix can decrypt secrets on first boot.

To copy the age key to an already-running host:

```bash
just rsync-sops <ip> 2222
```

## Adding a host

1. Create `modules/hosts/<name>/` with at minimum:
   - `default.nix` — declares `configurations.nixos.<name>.module`
   - `hardware.nix` — imports `_hw-generated.nix` + GPU/microcode
   - `networking.nix` — static IP, hostName, /etc/hosts
   - `_hw-generated.nix` — auto-generated (nixos-anywhere does this; or run `nixos-generate-config`)
2. Add the host's age public key to `.sops.yaml` and re-encrypt: `just sops`
3. Add any host-specific secrets to `secrets/sops/secrets.yaml`
4. Run `just dry <name>` to validate before deploying

## Distributed builds

Laptop offloads heavy builds to orion automatically. Other hosts can opt in:

```nix
# in the host's default.nix module body
nix.distributedBuildsOrion.enable = true;
```

Requires `/root/.ssh/nix-builder` on the client and the corresponding public key in
`modules/hosts/orion/default.nix` → `users.users.erik.openssh.authorizedKeys.keys`.

## Binary cache

orion runs `nix-serve` on `http://192.168.10.220:5000`. All hosts have it configured as
a high-priority substituter. The cache is warmed nightly at 03:00 by building all host
closures. Signing key is managed by sops-nix.

```bash
# Generate a new cache signing keypair (run on orion)
just cache-keygen
```

## Auto-upgrade health check

Hosts with `system.autoUpgrade.enable = true` get an automatic rollback guard: after each
unattended upgrade, `upgrade-health-check` verifies that `sshd` is still active. If not,
it rolls back the system profile and re-activates the previous generation, preventing a
bad upgrade from silently locking out remote access.

No configuration needed — the check activates automatically alongside `autoUpgrade`.

## Dev shell

```bash
direnv allow   # or: nix develop
```

Provides: `alejandra`, `statix`, `just`.
