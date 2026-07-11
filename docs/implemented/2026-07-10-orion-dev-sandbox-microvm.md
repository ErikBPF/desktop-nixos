# Orion dev sandbox — isolated MicroVM for remote Claude Code / VS Code

**Status:** ⚠️ Superseded by a container pivot (2026-07-11) — the `lander` MicroVM was built and briefly live (BIOS SVM enabled, tailnet-active, sshd 2222), then **replaced by the `gemini` NixOS container** (`modules/hosts/orion/gemini.nix`; commits `74a45fd`, `ed1417f`). Reason: a MicroVM cannot share orion's GPU/resources — the container shares CPU/RAM (GPU deferred). Live approach now: `ssh gemini` + VS Code Remote-SSH + in-container nix via the forwarded daemon. This doc is kept as the record of the MicroVM path and the pivot rationale.

**Author:** Erik (LLM-assisted structure)
**Date:** 2026-07-10

---

## 1. Goal

Run heavy dev work (Claude Code sessions + VS Code) on **orion** (Ryzen 9 5950X,
62 GB) instead of the laptop (8 cores, 31 GB), while guaranteeing the dev
environment **cannot degrade orion's existing responsibilities**. Access must be
seamless from the laptop (open an editor / a CC session "aimed at" orion with one
command). Usage is managed with **herdr** (agent multiplexer) and code is kept in
sync with **syncthing**.

## 2. Non-goals

- Not a second workstation profile on orion's host OS — the dev tools live *inside*
  a guest, not on the bare metal.
- Not a fleet-member host with a LAN IP / DHCP reservation (avoids coupling to
  `homelab-iac`). Reachability is via the guest's own tailnet identity — see §7.
- Not GPU-accelerated dev. The sandbox is deliberately blind to the GPU (that is
  the whole point). GPU work stays on orion's host / existing serving stack.
- No change to orion's nix-cache, sccache, binfmt-builder, or inference roles.

## 3. What orion already carries (the constraint set)

orion is **not** a spare box. It runs, today:

| Responsibility | Detail | Source |
|---|---|---|
| GPU training / inference | amdgpu RX 9070 XT; inference pinned to cores 1–15, amdgpu IRQ on CPU0 | `modules/hosts/orion/default.nix:56-60,165-186` |
| Fleet binary cache | `nix-serve` @ `http://orion:5000`, rollback-guard critical unit | `modules/services/nix-cache.nix`; `default.nix:67-72` |
| aarch64 cross builder | `boot.binfmt.emulatedSystems=["aarch64-linux"]` (archinaut closure) | `default.nix:90-91` |
| Build-offload target | accepts `nix-builder@laptop` over ssh-ng | `default.nix:140-143` |
| Shared sccache | `services.sccacheCache.enable` on tailnet | `default.nix:53-54` |
| HTPC / media | jovian (SteamOS), sunshine, hyprland | `default.nix:25` |

The sandbox must be structurally incapable of starving any of these.

## 4. 🔴 Blocker 0 — SVM is disabled in orion's BIOS

**MicroVM needs KVM. orion has no `/dev/kvm` today.** Verified 2026-07-10:

```
$ modprobe kvm_amd
modprobe: ERROR: could not insert 'kvm_amd': Operation not supported
$ journalctl -k | grep -i svm
kvm_amd: SVM not supported by CPU 2
```

The `svm` cpuid flag is advertised, but the kernel's runtime SVM probe returns
`EOPNOTSUPP` → **"SVM Mode / AMD-V" is toggled off in firmware** (same class as
kepler's documented BIOS-SVM block). `boot.kernelModules=["kvm-amd"]` already in
`hardware.nix:15` is therefore a no-op.

**Fix (one-time, physical, not remotely doable):** reboot orion → enter BIOS →
enable **SVM Mode / AMD-V** → save → boot. Then confirm `ls /dev/kvm` and
`lsmod | grep kvm_amd`. Nothing below works until this is done.

> `DECISION` — confirm you're willing to take orion down for a BIOS reboot, and
> whether SVM-always-on has any downside for the GPU serving workload (none known).

## 5. Architecture — reuse the kepler MicroVM pattern

A single **cloud-hypervisor MicroVM guest** on orion, defined exactly like kepler's
k3s nodes. `microvm.nix` is already a flake input (`flake.nix:113-116`); kepler is
the working reference (`modules/hosts/kepler/k3s-cluster.nix`).

New file `modules/hosts/orion/dev-sandbox.nix` →
`flake.modules.nixos.orion-dev-sandbox`, added to orion's import list in
`default.nix` (alongside the other `m.nixos.orion-*` modules). That module:

- `imports = [ inputs.microvm.nixosModules.host ];` (mirrors `k3s-cluster.nix:322`).
- Declares one guest via `microvm.vms.<name> = { config = mkGuest; }` +
  `microvm.autostart = [ "<name>" ]`.
- Builds the guest NixOS config (`mkGuest`) = a **slim dev profile** (see §8).

Guest `microvm` block (template from `k3s-cluster.nix:230-270`):

```nix
microvm = {
  hypervisor = "cloud-hypervisor";
  vcpu = 8;               # DECISION §6
  mem  = 24576;           # 24 GiB — DECISION §6
  interfaces = [{ type = "tap"; id = "vm-dev"; mac = "…"; }];
  shares = [{
    tag = "ro-store"; source = "/nix/store";
    mountPoint = "/nix/.ro-store"; proto = "virtiofs";
  }];
  volumes = [{ image = "root.img"; mountPoint = "/"; size = <GiB>; }];
};
```

Host-side pre-provisioning (guest state dir) via a `oneshot` unit ordered
`before = microvm@<name>.service`, and a raised 300 s start timeout — both copied
from `k3s-cluster.nix:433-459`.

## 6. Isolation — why it cannot hurt orion

| Lever | Setting | Effect |
|---|---|---|
| **GPU** | no device passthrough | guest never sees amdgpu — training/inference untouchable |
| **RAM** | `mem = 24576` (hard alloc) | 24 GB ceiling of 62; cannot balloon into the model working set |
| **Disk** | dedicated capped `root.img` on NVMe (`/var/lib/microvms/<name>`) | 336 GB free on NVMe; **not** `/scratch` (96% full) or `/opt/models` |
| **Cache/build** | guest runs its own store; no nix-serve / sccache / binfmt | cannot shadow orion's cache/builder roles |
| **CPU** | `vcpu` + `AllowedCPUs` + low `CPUWeight` on the `microvm@<name>` slice | guest yields to GPU-serving under contention — see below |

**CPU carve-out is the one hard tradeoff** — orion is 1 socket × 16 cores × 2
threads (SMT sibling map: physical core `c` = cpus `c` and `c+16`; CCD0 = cores
0–7, CCD1 = cores 8–15). Inference already claims cores **1–15**, IRQs on CPU0.
There is no fully idle core to hand the guest, so it must **share and yield**:

> `DECISION` — pick the carve-out policy:
> - **(a) Yield-only:** no `AllowedCPUs`, just a low `CPUWeight` (e.g. 20) on the
>   `microvm@` slice → guest uses spare cycles, GPU-serving always preempts.
>   Simplest; relies on the scheduler. **Recommended starting point.**
> - **(b) Pin to SMT siblings:** `AllowedCPUs = 24-31` (hyperthreads of CCD1) +
>   low `CPUWeight` → guest confined to secondary threads. Harder wall, but still
>   shares physical cores 8–15 with inference at the SMT level.
> - **(c) Reserve a core:** shrink the inference pool to 2–15 and give the guest
>   core 1 exclusively. Cleanest separation, costs inference one core.
>
> Whichever we pick, `CPUWeight` must guarantee the 24/7 llama-chat path wins when
> `orionGpu.profile` flips to `"inference"`.

## 7. Networking — private NAT bridge + tailscale inside the guest

kepler's k3s guests are **not** tailnet members; they reach the tailnet only via
kepler's `tailscale0` MASQUERADE. For a dev box we want it reachable **directly
from the laptop, roaming**, so the guest runs its own `tailscaled`.

- Host: new NAT bridge `br-dev` (e.g. `10.100.0.1/24`), `networking.nat` with
  `internalInterfaces=["br-dev"]`, `externalInterface="enp4s0"` (**iptables**
  backend — the fleet does not use nftables; see `k3s-cluster.nix:378`). The tap
  `vm-dev` is bridged into `br-dev` via `systemd.network` match rules (template
  `k3s-cluster.nix:342-385`). `net.ipv4.ip_forward` is `0` today → NAT enables it.
- Guest: static IP on `10.100.0.0/24`, gateway = `br-dev`, plus
  `services.tailscale` reusing the module at `modules/networking/tailscale.nix`
  (sops `tailscale_authkey` OAuth secret, `authKeyFile`). Guest joins the tailnet
  as its own node → reachable as `<name>` by MagicDNS from anywhere.
- The guest is a minimal MicroVM → it must load bridge/netfilter modules itself
  (`boot.kernelModules=["br_netfilter" "overlay"]` + sysctls, like
  `_k3s-node.nix:51-56`).

> `DECISION` — confirm tailscale-in-guest (recommended, roaming-friendly) vs.
> NAT-only + an orion port-forward (simpler, but only reachable through orion).

## 8. The guest — a slim dev profile

The dev-agent modules live only in `profile-desktop` today
(`modules/profiles/desktop.nix`) and are **absent from orion's host**. The guest
gets just the dev slice, not the GUI stack:

- **home modules** (from `flake.modules.home.*`): `claude-code`, `codex`,
  `opencode`, `vscode` (for the VS Code Remote-SSH server), `herdr`.
- **nixos**: `profile-base` (sshd on 2222, distributed-builds, home-manager),
  `tailscale`, `<guest>-syncthing`, the dev-language modules
  (`dev-python`/`go`/`javascript`/… as needed), plus openssh.
- **No** xserver/hyprland/sddm/jovian/sunshine — Remote-SSH is headless.

> `DECISION` — which language toolchains to preinstall in the guest, and whether
> to reuse the laptop's `home.profile-desktop` dev subset or curate a smaller list.

## 9. Access — seamless from the laptop

- Laptop `~/.ssh/config`: `Host <name>` → guest tailnet IP, `Port 2222`, `User erik`.
- **VS Code Remote-SSH** targets that host — native editor, code on the guest's
  fast local disk next to the compute.
- Shell alias `<name>` (in the laptop dev env) → `ssh -t <name> tmux new -A -s dev`
  landing in **herdr**, which multiplexes claude-code / codex / opencode with
  per-agent state. herdr = the "control usage" surface; the MicroVM caps *compute*,
  herdr manages *sessions*.

> `DECISION` — guest name (space-themed sibling: `lander` / `probe` / `shuttle`,
> or plain `orion-dev`). Drives the tailnet name, ssh alias, and module names.

## 10. Files — remote-primary + syncthing mirror

Register the guest as a **new syncthing device** and share one **dev-workspace**
folder guest ↔ laptop. Files live on the guest (fast); the laptop keeps a
read/write mirror for offline/backup. orion's own syncthing folders are untouched.

- Add `<name>_id = "…"` to `modules/secrets.nix` `syncthingDeviceIDs` (public IDs,
  plain option — not a sops secret). Generate the guest's ID on first boot.
- Add a `hosts.<name>` entry in `modules/services/syncthing-fleet.nix` with
  `devices=["laptop"]` and a `dev-workspace` attrset folder (auto `syncAll` +
  `ensureDir`); add its label to `folderLabels`. Add the matching folder to the
  laptop host entry. This auto-produces `m.nixos.<name>-syncthing`.
- Peer addressing is `tcp://<peer>:22000` — works because the guest is a tailnet
  node with a resolvable name (§7).

> `DECISION` — one shared workspace root (e.g. `~/dev`) vs. per-repo folders.
> Beware: running agents on a bidirectionally-synced tree can create conflicts —
> remote-primary (edit only on the guest, mirror is backup) avoids that.

## 11. Credentials in the guest

Claude Code / codex / opencode carry their own auth (herdr does not own it).

> `DECISION` — seed keys via sops into the guest, or do an interactive
> `claude login` / device-code flow on first boot. sops is reproducible;
> interactive is simpler for a single box.

## 12. Rollout & verification

1. **BIOS**: enable SVM on orion → `ls /dev/kvm`, `lsmod | grep kvm_amd`. (Blocker 0.)
2. Add `modules/hosts/orion/dev-sandbox.nix` + wire imports. `git add` it (untracked
   files are invisible to nix eval).
3. `just lint && just fmt-check`; `just dry orion` — skim the diff for surprises.
4. `just switch-orion`. Verify **orion's own** services survived:
   `systemctl status nix-serve sccache-cache`; a GPU-serving smoke test; confirm
   inference core pinning intact.
5. Verify the guest: `systemctl status microvm@<name>`; from the guest,
   `tailscale status`; from the laptop, `ssh <name>` + VS Code Remote-SSH connect.
6. Under load: run a build in the guest while a GPU job runs on the host; confirm
   the GPU job is not starved (validates the §6 `CPUWeight` choice).

## 13. Risks

- **BIOS SVM** is a physical prerequisite and a reboot (Blocker 0).
- **CPU contention** with inference — mitigated by `CPUWeight`, but needs the §12.6
  load test to prove.
- **MicroVM guest closure** builds on orion (or the laptop, cached to orion) — first
  build is heavy; subsequent are cached.
- **Auto-upgrade**: orion upgrades first in the fleet (04:00); a guest that
  `autostart`s must survive host generation switches (kepler's `microvm@` units do).

## 14. Open decisions (summary)

| # | Decision | Recommendation |
|---|---|---|
| D0 | BIOS SVM reboot OK? | Required — no path without it |
| D1 | CPU carve-out policy (§6 a/b/c) | (a) yield-only + low CPUWeight to start |
| D2 | tailscale-in-guest vs NAT+port-forward (§7) | tailscale-in-guest |
| D3 | guest name (§9) | TBD (space theme) |
| D4 | language toolchains in guest (§8) | curate minimal |
| D5 | workspace layout / sync direction (§10) | remote-primary, single root |
| D6 | credential seeding (§11) | interactive first-boot login |
