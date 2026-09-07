# Apollo: RTX 3070 plus two RTX 5060 Ti cards

**Status:** Preparation in progress; new cards absent and hardware acceptance pending.

## Selected behavior and implementation plan

Keep the existing RTX 3070 and prepare two incoming RTX 5060 Ti cards on Apollo.
Use the existing native NVIDIA driver, persistence service and conservative
power service; identify each present GPU by PCI model and issue mutations by
UUID. Missing incoming cards do not block preparation. Unknown models, failed
inventory and unsupported power limits fail visibly; a failure on one card does
not skip the remaining known cards. NVIDIA CDI generation requires successful
power-policy application. This does not police arbitrary host CUDA clients or
revoke an already-generated CDI file if an operator later changes settings.

| Card | PCI device | Power ceiling | Graphics clock policy |
|---|---|---:|---|
| RTX 3070, including current LHR card | 2484 / 2488 | 170 W | Firmware-managed; prior lock reset |
| Each RTX 5060 Ti | 2D04 | 145 W, provisional | Firmware-managed; prior lock reset |

These are power/clock defaults, **not a verified voltage undervolt**. Actual V/F
curve tuning requires supported controls and stability qualification on each
physical card. The 5060 Ti ceiling is an engineering starting point (~81% of
NVIDIA's reference 180 W), accepted only if the actual board's reported range
permits it. NVIDIA's native command validates that range; warnings are failures.
Limits apply at boot and when the power service restarts. Each known card also
receives `--reset-gpu-clocks`, removing any earlier graphics-clock lock.
The operator reported a PCIe extender on Kepler as a possible cause of the
3070 faults and requested stock frequencies; that cause is not yet proven. After a driver reset
or unload/reload, reapply and verify them before resuming GPU work.

The existing 595.99.02 driver supports both models. Blackwell requires **open**
kernel modules; Ampere also supports them. Remove the redundant proprietary
`boot.extraModulePackages` injection and let NixOS select the open modules.
Preserve the exact host/guest kernels, networking, storage and paused household
inference. No workload migration or GPU passthrough is part of this change.

Verification slice: extend the effective GPU options test (open-only modules,
CDI dependency, exact kernels and retention), then run the production power
script with fake single-card, reordered three-card, unknown-card, empty,
inventory-failure and per-device-failure cases. Run ShellCheck, normal host
checks and full build; independent review and green hosted CI precede staging.
Source tests do not prove a card that is not installed works.

## Boot staging and rollback

This changes kernel-module flavor: use **boot staging**, no live driver switch
or automatic reboot. At September 7 preflight, running generation 15 used the
accepted closed driver; another deployment had advanced the default to 18 and
retained only 16–18 in the menu. The first preparation restored 15–19.
Keep six entries for this follow-up so staging generation 20 retains accepted
generation 15. Recount immediately before staging: six covers 15–20 only. If the profile advanced again, preserve
the accepted generation before proceeding; do not silently prune it.

```sh
ssh -p 2222 erik@192.168.10.174 \
  'readlink -f /run/current-system; readlink -f /run/booted-system/kernel
   readlink -f /nix/var/nix/profiles/system
   readlink -f /nix/var/nix/profiles/system-15-link
   sudo bootctl list --no-pager'
just dry apollo
just build apollo
just deploy-rs-boot apollo
```

After staging, verify the new default, the accepted generation's actual boot
entry and unchanged running system/kernel. Return retention to three only after
open-driver and three-card hardware acceptance. The old closed-driver entry is
a rollback for the existing 3070; it cannot operate the incoming Blackwell cards.

## Apply clock correction without a driver switch

After review, the production helper can apply power limits and reset graphics
clock locks on the running driver, without replacing remote configuration:

```sh
ssh -p 2222 erik@192.168.10.174 'sudo bash -s' < modules/hosts/apollo/_gpu-power.sh
ssh -p 2222 erik@192.168.10.174 \
  'nvidia-smi --query-gpu=uuid,name,power.limit --format=csv; nvidia-smi -q -d CLOCK'
```

Boot-stage the same source through the owner recipe for persistence. The old
running service still contains the historical cap until the prepared generation
boots; restarting that old service can reintroduce it. Reapply this helper if
that happens. No driver reload or reboot is required for the clock reset itself.

## Arrival and acceptance

Exact card manufacturer/model/VRAM and PSU model/wattage are still required for
physical acceptance. The observed board is MACHINIST X99-MR9S; confirm its actual
revision, usable slot spacing, connector clearance and airflow with all three
cards. Size PSU/cabling against actual board limits, CPU and other hardware,
including startup/transients: the 460 W configured GPU sum is not PSU sizing.
The reference stock GPU sum is 580 W before CPU and other loads. Do not rely on
software limits before the driver/service has initialized.

After a planned power-off installation and boot into the prepared generation:

```sh
ssh -p 2222 erik@192.168.10.174 \
  'cat /proc/driver/nvidia/version
   nvidia-smi --query-gpu=uuid,name,pci.bus_id,pci.device_id,memory.total,power.limit,power.min_limit,power.max_limit --format=csv
   systemctl status nvidia-conservative-clocks nvidia-persistenced nvidia-container-toolkit-cdi-generator --no-pager
   nvidia-smi -q -d CLOCK
   systemctl --failed --no-pager'
just diagnose-apollo-worklab
```

Require one 3070 and two 5060 Ti identities, open modules, all three applied
power ceilings, default graphics-clock policy, NVIDIA CDI inventory for all cards,
automatic `lan0` networking, NFS and five healthy guest nodes. Inventory alone
is not compute acceptance. Use the existing bounded CUDA correctness procedure
in [GPU exchange](kepler-apollo-gpu-exchange.md), selecting each UUID through
`CUDA_VISIBLE_DEVICES`, then a bounded combined run. Validate CUDA/PTX support
for Blackwell before running an artifact built for Ampere. Record each result,
temperature and current-boot Xid faults. The earlier closed-driver 3070 test does
not qualify this open-driver configuration or the new cards. No voltage offset
or aggressive clock tuning is accepted without those physical tests.

## Primary references

- [NVIDIA open-module requirements](https://download.nvidia.com/XFree86/Linux-x86_64/595.71.05/README/kernel_open.html)
- [Exact 595.99.02 supported PCI IDs](https://raw.githubusercontent.com/NVIDIA/open-gpu-kernel-modules/595.99.02/README.md)
- [Native power and clock controls](https://docs.nvidia.com/deploy/nvidia-smi/index.html)
- [RTX 5060 family reference specifications](https://www.nvidia.com/en-us/geforce/graphics-cards/50-series/rtx-5060-family/)
- [CUDA Blackwell compatibility](https://docs.nvidia.com/cuda/blackwell-compatibility-guide/index.html)
