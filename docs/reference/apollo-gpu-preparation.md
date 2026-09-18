# Apollo: the two RTX 5060 Ti cards

**Status:** Live. The retired RTX 3070 is gone; both Blackwell cards are
installed, capped at 150 W and driven by the open kernel modules.

## Selected behavior

Apollo runs two RTX 5060 Ti cards on the native NVIDIA driver, persistence
service and conservative power service; each present GPU is identified by PCI
model and mutated by UUID. Unknown models, failed inventory and unsupported
power limits fail visibly; a failure on one card does not skip the other.
NVIDIA CDI generation requires successful power-policy application. This does
not police arbitrary host CUDA clients or revoke an already-generated CDI file
if an operator later changes settings.

| Card | PCI device | Power ceiling | Graphics clock policy |
|---|---|---:|---|
| Each RTX 5060 Ti | 2D04 | 150 W (firmware minimum) | Firmware-managed; prior lock reset |

150 W is the lowest ceiling the board firmware accepts, established by live
evidence on 2026-09-08: both boards report a 150–180 W range and the earlier
145 W attempt silently failed, leaving both cards at 180 W. `nvidia-smi`
validates the requested range and warnings are failures. The retired RTX 3070
(`2484`/`2488`) is no longer a known device, so a 3070 present in inventory is
refused rather than capped. Limits apply at boot and when the power service
restarts. Each known card also receives `--reset-gpu-clocks`, removing any
earlier graphics-clock lock.

The 150 W ceiling is a power/clock default, **not a verified voltage undervolt**.
Actual V/F curve tuning requires supported controls and stability qualification
on each physical card. After a driver reset or unload/reload, reapply and verify
the limits before resuming GPU work.

Blackwell requires **open** kernel modules, which this host selects for both
cards. Preserve the exact host kernels, networking, storage and paused household
inference. No workload migration or GPU passthrough is part of this change.

Verification slice: the effective GPU options test (open-only modules, CDI
dependency, clocks service, exact power limits) plus the production power script
run against fake two-card, unknown-card, retired-3070, empty, inventory-failure
and per-device-failure cases. Source tests do not prove the installed cards work.

## Boot staging and rollback

This changes kernel-module flavor: use **boot staging**, no live driver switch
or automatic reboot.

```sh
ssh -p 2222 erik@192.168.10.174 \
  'readlink -f /run/current-system; readlink -f /run/booted-system/kernel
   readlink -f /nix/var/nix/profiles/system
   sudo bootctl list --no-pager'
just dry apollo
just build apollo
just deploy-rs-boot apollo
```

After staging, verify the new default, the accepted generation's actual boot
entry and unchanged running system/kernel. Return retention to the host
baseline only after open-driver and two-card hardware acceptance.

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

## Acceptance

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

Require two 5060 Ti identities, open modules, both applied power ceilings,
default graphics-clock policy, NVIDIA CDI inventory for both cards, automatic
`lan0` networking and NFS. Inventory alone is not compute acceptance. Use the
bounded CUDA correctness procedure in
[GPU exchange](kepler-apollo-gpu-exchange.md), selecting each UUID through
`CUDA_VISIBLE_DEVICES`, then a bounded combined run. Record each result,
temperature and current-boot Xid faults. The configured GPU sum is now 300 W;
that is not PSU sizing — size cabling and the PSU against the actual board
limit, CPU and startup transients (the two cards' stock sum is 360 W).

## AI trial storage

Apollo declares `apollo-ai-storage.service` to create private operator-owned
`/mnt/data/ai/{models,cache}` directories (0700). The service requires the
existing data-array mount and asserts that `/mnt/data` is a mount point before
creating anything, so a missing or degraded mirror fails loudly instead of
filling the root pool. Future inference units must independently require the
mirror before using it.

Initial operational cache budget is 256 GiB, checked before downloads; it is
not an enforced filesystem quota. Set per-trial `HF_HOME`, `XDG_CACHE_HOME`,
`TORCH_HOME` and `CUDA_CACHE_PATH` beneath the cache directory. Do not redirect
all operator applications globally. Start trials with `MemoryMax=64G`,
`MemorySwapMax=0` and `CPUQuota=400%`; these limits reserve no host capacity,
and Nix still permits six build jobs with two cores each.

## Primary references

- [NVIDIA open-module requirements](https://download.nvidia.com/XFree86/Linux-x86_64/595.71.05/README/kernel_open.html)
- [Native power and clock controls](https://docs.nvidia.com/deploy/nvidia-smi/index.html)
- [RTX 5060 family reference specifications](https://www.nvidia.com/en-us/geforce/graphics-cards/50-series/rtx-5060-family/)
- [CUDA Blackwell compatibility](https://docs.nvidia.com/cuda/blackwell-compatibility-guide/index.html)
