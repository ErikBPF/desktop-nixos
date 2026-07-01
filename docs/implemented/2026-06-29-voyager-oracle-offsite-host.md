# Voyager Oracle Offsite Host

**Date:** 2026-06-29
**Status:** Superseded (graduated 2026-07-01) — the *goal* shipped, the *method*
did not. Kept as the as-built record.
**Owner:** erik
**Scope:** Convert the Oracle Ubuntu VM at `129.148.45.145` into the fleet's
`voyager` offsite backup receiver, but only after validating the same NixOS
configuration in a small VM on `orion`.

## Superseded — read this first (2026-07-01)

The **goal** — Oracle `voyager` as the fleet's off-premise append-only restic
receiver — **shipped** and is the as-built record in
[`../implemented/2026-06-30-offsite-dr-crown-jewels.md`](2026-06-30-offsite-dr-crown-jewels.md)
(voyager receives tofu-state, the `.env.sops` bundle, and the OpenBao snapshot).

The **method** in this doc did **not** survive contact:

- **Install path.** The disko `/dev/sda` wipe via `deploy-voyager`/nixos-anywhere
  (§4, §9) was abandoned — the 1 GB micro can't kexec and Oracle free-tier
  `custom-image-count=0` blocks image import. voyager was brought up **in place
  via nixos-infect** instead; the host modules (`modules/hosts/voyager/*`) use
  by-label filesystems, **not** the §4 disko layout.
- **Validation path.** The orion VM-tap dance (§5–§6: `eth0`/`ens3`,
  `10.88.0.2`, MASQUERADE/FORWARD) was not the final route; iteration happened on
  the infected host directly.
- **Switch tooling.** `switch-voyager` now goes through **deploy-rs**
  (`implemented/2026-06-30-deploy-rs-as-deploy-standard.md`), not the recipes
  sketched here.

Treat §4, §5, §6, §9 as historical. The receiver behaviour (§3, §5's restic-REST
`--append-only --private-repos` findings) is accurate and live.

### One live gap, not covered elsewhere

`--append-only` means the off-premise repo **never prunes → grows unbounded**, and
there is currently **no disk-fill alert on voyager `/srv/backups`**. Follow-up:
either a periodic privileged prune, or a `node_filesystem_avail`-based Grafana
alert on voyager. Tracked here until built; §10 "append-only retention" is the
origin of this item.

## 1. Goal

Use the Oracle VM as a real source-backed stack host for offsite backups.

Constraints:

- Back up config files only for now, not media, bulk datasets, or full local
  restic repository mirrors.
- Keep Headscale out of scope for this slice. The current fleet remains
  Tailscale SaaS based; Headscale can be explored later.
- Do not install NixOS on Oracle until the configuration is validated in a VM
  on `orion`.
- The Oracle install is destructive: it wipes `/dev/sda` and removes the
  existing `nanda-colors` Ubuntu/Docker workload.

## 2. Current Oracle VM facts

SSH access works with the available key:

```bash
ssh ubuntu@129.148.45.145 'hostname; id -un; uname -a'
```

Observed state:

| Item | Value |
|---|---|
| Public IP | `129.148.45.145` |
| SSH user | `ubuntu` |
| Hostname | `nanda-colors` |
| OS | Ubuntu 24.04, Oracle kernel |
| Boot | EFI |
| Disk | single `/dev/sda` Oracle `BlockVolume`, 46.6 GB |
| Free root space | about 36 GB before conversion |
| RAM | about 1 GB |
| Swap | none |
| sudo | passwordless sudo works |
| Tailscale / Headscale | neither installed |

Existing workload found on the VM:

| Container | Image / role |
|---|---|
| `nanda-colors-cloudflare` | `cloudflare/cloudflared:latest` |
| `nanda-colors-frontend` | frontend app |
| `nanda-colors-backend` | backend app |
| `nanda-colors-db` | `postgres:15-alpine` |
| `nanda-colors-redis` | `redis:7-alpine` |

Decision: this workload may be removed, but only by the final Oracle NixOS
install after the validation gate below passes.

## 3. Target shape

`voyager` becomes a minimal NixOS stack host:

- `profile-base` + `profile-server` for the fleet baseline.
- SSH on port `2222` with the fleet OpenSSH policy.
- Tailscale client for production reachability.
- Rootless Podman via the existing `containers` module.
- `homelab.compose` orchestration to clone/pull the `servarr` repo and start
  only the `voyager/offsite.yml` stack.
- `/srv/backups/restic` as the fixed receiver path.

The stack side is `references/repos/servarr/machines/voyager/offsite.yml`:

- `restic-rest-init` creates `/data/kepler/.htpasswd` for `--private-repos`.
- `restic-rest` runs `restic/rest-server:0.13.0` with
  `--append-only --private-repos`.
- Backups land under `/srv/backups/restic` on the host.

Kepler offsite scope is intentionally narrowed:

- `kepler/sync.yml` offsite job backs up `/config` only.
- The previous `/backups/restic-repo` local mirror push is removed for this
  slice.

## 4. NixOS config staged so far

New host modules staged under `modules/hosts/voyager/`:

| File | Purpose |
|---|---|
| `default.nix` | Registers `configurations.nixos.voyager`, imports baseline modules, and defines the VM variant. |
| `hardware.nix` | Oracle-compatible EFI + qemu-guest + single `/dev/sda` disko layout. |
| `networking.nix` | Production hostname `voyager`, DHCP on `ens3`, Tailscale client mode, restic port allowed on `tailscale0`. |
| `compose.nix` | Declares the `offsite` stack and creates `/srv/backups/restic`. |

`justfile` changes staged so far:

| Recipe / value | Purpose |
|---|---|
| `ip_voyager := "129.148.45.145"` | Oracle public IP handle. |
| `_host-ip voyager` | Allows fleet recipes to resolve Voyager. |
| `switch-voyager` | Future deploy after NixOS is installed. |
| `deploy-voyager` | Future `nixos-anywhere` install path from Ubuntu `ubuntu@129.148.45.145`. Destructive. |
| `voyager-vm-build` | Builds `.#nixosConfigurations.voyager.config.system.build.vm`. |
| `voyager-vm-start` | Starts the validation VM on Orion under `/scratch/voyager-vm`. |
| `voyager-vm-stop` | Stops the validation VM and removes temporary tap/NAT rules. |
| `voyager-vm-smoke` | Intended smoke test for SSH + `podman-compose-offsite.service` + restic REST. |

`README.md` has a draft host row for `voyager`.

## 5. Validation evidence so far

Flake evaluation initially failed because new files were untracked. Staging the
new `modules/hosts/voyager/*.nix` files fixed visibility.

Production toplevel dry-evaluates:

```bash
nix build .#nixosConfigurations.voyager.config.system.build.toplevel --dry-run --show-trace
```

Result: Nix reported derivations to build/fetch, not an evaluation error.

VM runner dry-evaluates:

```bash
nix build .#nixosConfigurations.voyager.config.system.build.vm --dry-run --show-trace
```

Result: Nix reported the VM derivations to build/fetch, not an evaluation error.

VM runner builds:

```bash
just voyager-vm-build
```

Result: build succeeded.

Orion validation host facts:

| Item | Value |
|---|---|
| Host | `orion` / `192.168.10.220` |
| RAM | enough available for 1 GB VM |
| Scratch disk | `/scratch`, about 417 GB free |
| `/dev/kvm` | not visible in SSH session; QEMU falls back to `kvm:tcg` |
| `qemu-system-x86_64` | supplied by the Nix VM runner, not host PATH |
| sudo | passwordless sudo works |

### Disko install path validated (2026-06-29)

The `build.vm` runner uses an ephemeral qcow2 and never exercises the declared
disko layout. To validate the real `/dev/sda` partitioning + install — the same
path `deploy-voyager` runs on Oracle — without touching Oracle:

```bash
just voyager-vm-test   # nixos-anywhere --vm-test --flake .#voyager
```

Result: passed. The test partitioned the disk per disko, installed, booted, and
reached `local-fs.target`, confirming the GPT layout (512 M vfat ESP at `/boot`
+ btrfs root with `root`/`home`/`nix`/`log` subvolumes, zstd, noatime) mounts and
systemd-boot installs correctly. This closes the largest pre-Oracle unknown.

### Receiver validated end-to-end (2026-06-29)

After the `eth0` fix the VM became reachable and the `offsite` stack was brought
up on it (clone seeded manually — see §7 on the deploy-key gap). Results:

- `restic-rest` enforces auth: unauthenticated and bad-credential requests → 401.
- `--private-repos` isolation holds: user `kepler` can use `/kepler/` (POST
  `?create=true` → 200) but `/other/` → 401, and a non-matching path like
  `/kepler2/` → 401.
- A real restic client round-trips: `init` → `backup` (snapshot saved) →
  `snapshots` (lists it).
- `--append-only` holds: `forget --prune` left the snapshot in place.

**Bug found and fixed (`servarr` `offsite.yml`).** `restic-rest-init` wrote the
htpasswd to `/data/kepler/.htpasswd`, but rest-server runs with
`--htpasswd-file /data/.htpasswd` and auto-created an *empty* file there — so it
logged "No user exists" and **every** request 401'd, including valid ones. Fixed
the init to write `/data/.htpasswd` (data root, not a per-repo subdir). This
change must be committed + pushed in the `servarr` repo (gate item).

## 6. Validation attempts and current blocker

### Attempt 1 — QEMU user-mode forwarding

The first VM variant used QEMU SLiRP `forwardPorts`:

- host `192.168.10.220:2229` → guest `2222`
- host `192.168.10.220:8009` → guest `8000`

This was rejected as insufficient because it tests services through Orion's IP,
not through an independent VM IP. It also obscures whether a future host behaves
like a real peer.

### Attempt 2 — routed tap network

The VM variant was changed to use a dedicated tap network:

- Orion tap: `voyager-vm-tap`, `10.88.0.1/24`
- Voyager VM: `10.88.0.2/24`
- Default gateway: `10.88.0.1`
- Temporary NAT on Orion: `10.88.0.0/24` out via `enp4s0`

Start recipe creates:

- `voyager-vm-tap`
- `net.ipv4.ip_forward=1`
- `iptables` MASQUERADE and FORWARD rules

Stop recipe removes:

- the MASQUERADE rule
- the FORWARD rules
- `voyager-vm-tap`

Current blocker: QEMU starts and the tap exists, but Orion cannot yet reach
`10.88.0.2`:

```text
voyager-vm-tap UP 10.88.0.1/24
ping 10.88.0.2 -> 100% packet loss
/dev/tcp/10.88.0.2/2222 -> No route to host
```

The last known QEMU command includes the tap backend:

```text
-net nic,netdev=user.0,model=virtio
-netdev tap,id=user.0,ifname=voyager-vm-tap,script=no,downscript=no
```

### Root cause (identified) and fix

The blocker is the guest interface name. The VM variant configured a static IP
and the port-8000 firewall rule on `eth0`, but NixOS keeps predictable interface
names by default, so the virtio NIC enumerates as `ens3` (the same name
production `networking.nix` uses). The address therefore landed on a nonexistent
`eth0` → the guest had no L3 address → `ping 10.88.0.2` from Orion failed at the
tap. (The ping is direct delivery from `10.88.0.1` to the tap, not forwarded
traffic, which rules out the MASQUERADE/FORWARD rules as the cause.)

Fix applied: `boot.kernelParams = ["net.ifnames=0"]` in `vmVariant`, forcing
real `eth0` so both the static address and the firewall rule bind correctly. The
QEMU NIC was also switched from the legacy `-net nic,netdev=…` form to
`-device virtio-net-pci,netdev=…,mac=52:54:00:88:00:02` (stable MAC, modern
syntax).

### What the VM proves — and what it does not

The VM proves: boot, disko layout, rootless Podman, the `offsite` compose stack,
and a working restic REST receiver. It deliberately uses static `eth0` on a tap
with Tailscale disabled, so it does **not** exercise the production network path:
DHCP on `ens3`, Tailscale bring-up, or the receiver firewall rule that in
production is bound to `tailscale0` (not `eth0`). Those are first tested on the
destructive Oracle target — an accepted residual risk recorded in the gate.

## 7. Known issues discovered while validating

- `profile-server` already imports `m.nixos.orchestration`; importing it again in
  `voyager/default.nix` caused duplicate option declarations.
- `home-manager-base` already imports `m.home.profile-base`; manually importing
  it again in Voyager duplicated the GPG pinentry option.
- The VM output runner is named `run-voyager-vm-vm`, not `run-voyager-vm`; the
  recipe now discovers the runner under `result/bin/*`.
- Copying locally-built VM closures to Orion failed signature checks; the VM
  start recipe uses `nix copy --no-check-sigs` for this local validation closure.
- Orion's login shell is Fish, so remote recipe scripts must explicitly execute
  with Bash.
- Fleet SSH is port `2222`; the smoke test initially tried port `22`.
- QEMU default SLiRP networking had to be force-replaced with
  `lib.mkForce config.virtualisation.qemu.networkingOptions` to avoid duplicate
  `user.0` netdev IDs.
- The guest NIC enumerates as `ens3`, not `eth0`, under predictable naming —
  the static VM IP was on the wrong interface (see §6 root cause).
- `podman-compose-offsite` is a rootless **user** unit (`systemd.user.services`
  in `orchestration.nix`); the smoke test must query it with
  `systemctl --user`, not system scope, or it always reports `not-found`. The
  unit also takes minutes to start, so the smoke test now gates on SSH
  reachability and only *reports* the unit state rather than requiring it active.
- `servarr-pull` clones `git@github.com:` over SSH and needs the host's git
  deploy key at `/home/erik/.ssh/id_ed25519`. The validation VM has no such key
  (only the sops age key is shared in), so `servarr-pull` fails there; the clone
  was seeded manually for validation. The production Oracle host must provision
  the deploy key (sops) before `servarr-pull` will work — a gate prerequisite.
- First-boot race: with `systemd.user.startServices = false`, the linger user
  session reaches `default.target` *before* home-manager activation writes and
  enables the `servarr-pull`/`podman-compose-*` user units, so they do not auto
  start on the very first boot (a reload does not retro-start `wantedBy` units).
  On a normal deploy the session is already up during activation, so this only
  bites the first boot; in practice run `just pull-servarr voyager` once after
  install to kick the first sync.

## 8. Next steps

1. Finish the Orion VM validation.
2. From Orion, verify whether the guest sees `eth0` and owns `10.88.0.2`.
3. If needed, adjust the VM variant interface name away from `eth0` or pass a
   predictable MAC/link rule.
4. Once SSH works, run:
   ```bash
   just voyager-vm-smoke
   ```
5. Verify the offsite compose unit specifically:
   ```bash
   ssh -p 2222 erik@10.88.0.2 'systemctl --user status servarr-pull.service podman-compose-offsite.service --no-pager'
   curl -i http://10.88.0.2:8000/
   ```
6. Run a restic init/snapshot test from a disposable local repo against
   `http://10.88.0.2:8000/kepler/` using the Voyager test credentials.
7. Only after the VM path passes, deploy to Oracle with `just deploy-voyager`.

## 9. Oracle cutover gate

Do not run `just deploy-voyager` until all are true:

- `just voyager-vm-test` passes (disko `/dev/sda` install path boots).
- `just voyager-vm-smoke` passes.
- A restic client can initialize and write to the VM receiver.
- The receiver enforces auth and `--private-repos` layout.
- The offsite scope is confirmed as config-only.
- The `servarr` changes are committed and pushed so the production host can pull
  them by Git.
- Tailscale auth/secrets are valid for the new host **and** the tailnet ACL
  grants `kepler → voyager:8000` (default-deny tailnet; land the grant in
  `homelab-iac` first, per the leaf-first rule).
- **Oracle disk attachment confirmed paravirtualized**, not iSCSI: on the live
  Ubuntu, `lsblk`, `ls -l /dev/disk/by-path`, and `iscsiadm -m session` agree
  that `/dev/sda` is virtio. If it is iSCSI, `hardware.nix` needs iSCSI initrd
  handling before any wipe.
- **Out-of-band recovery exists before the wipe**: Oracle serial console access
  is verified working, and an Oracle BlockVolume backup/snapshot of the boot
  volume is taken (single disk, destructive — this is the only rollback).
- **VCN security list allows inbound 2222** (fleet SSH port) so break-glass SSH
  survives the cutover. Tailscale is outbound-only and needs no ingress rule.
- The git deploy key for the `servarr` repo is provisioned on the host (sops →
  `/home/erik/.ssh/id_ed25519`) so `servarr-pull` can clone; run
  `just pull-servarr voyager` once after install to seed the first sync (the
  first-boot user-unit race means it will not auto-start on boot 0).
- The kepler local restic mirror is **kept** until Voyager passes this gate;
  removing it is a follow-up after offsite is proven, so backup coverage never
  drops to zero.
- The user confirms the destructive Oracle install.

When the gate passes, the planned Oracle command is:

```bash
just deploy-voyager
```

Expected impact:

- Wipes Oracle `/dev/sda`.
- Removes the Ubuntu `nanda-colors` Docker/cloudflared stack.
- Installs NixOS `.#voyager`.
- Future management moves to `just switch-voyager`, `just pull-servarr voyager`,
  and `just kick-stack voyager offsite`.

## 10. Decisions and open questions

Resolved:

- **Alloy: dropped.** Removed from `voyager/default.nix` imports — too heavy for
  ~1 GB RAM on a backup-only host.
- **Low-memory headroom: added.** `zramSwap.enable` plus `boot.tmp.useTmpfs =
  false` (cf. archinaut) so the 1 GB / no-swap box survives activation and
  rootless-podman startup.
- **ESP generation limit: 2** (was 3) to keep kernel/initrd copies inside the
  512 M ESP (cf. kepler ESP-overflow lesson).
- **Local mirror sequencing:** keep kepler's local restic mirror until Voyager
  is validated; remove it only in a follow-up (see gate).

Deferred until the VM path runs cleanly:

- **Oracle storage volume:** root BlockVolume only vs a dedicated larger
  BlockVolume for `/srv/backups/restic`. Decide after local validation, sized to
  the actual config-only repo footprint.

Open:

- **Append-only retention:** `--append-only` blocks remote `forget`/`prune`, so
  the repo grows unbounded. Decide a maintenance path (separate privileged
  credential run, or accept growth + disk alert) before relying on it long-term.
- Whether the validation VM should become a reusable generic VM harness for other
  host configs.
- Whether to later replace Tailscale SaaS with Headscale or only add Headscale as
  a separate experiment.
