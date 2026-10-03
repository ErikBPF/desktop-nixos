# Kepler guest clocksource canary and persistent rollout — October 2, 2026

**Status:** All six guests booted persistent `kvm-clock` and passed final health
checks. The requested one-at-a-time rollout failed through shared host
dependencies; the final preservation fix deployed without guest restarts.
Merged to main. A subsequent serial worker-only closure restoration passed
peer boot/process continuity and workload recovery gates; storage-delay
attribution remains open.

## Original runtime canary (historical)

This section preserves the original cp-1-only scope and evidence. Its
not-deployed statements and cp-1-only assertion describe that earlier phase;
use the final rollout check below for the current all-guest configuration.

The operator requested “lets do the proposed test” after cp-1's previous boot
showed a large guest clock jump, CPU 1 timer wakeup failures and RCU stalls.
Those failures preceded kubelet heartbeat loss and k3s API timeouts. The exact
hypervisor/kernel trigger is unproven. Test `kvm-clock` on cp-1 alone; keep the
host and all other guests unchanged.

At the original preflight, the running guests used Linux 7.2.3 and K3s 1.35.7. This source checkout evaluated
K3s 1.36.4 and different runner closures for all six guests. A host deployment
would confound the experiment and could bounce multiple control planes. The
declarative cp-1-only kernel parameter is prepared in
`modules/hosts/kepler/k3s-cluster.nix`, but is **not deployed**. The initial
experiment uses the kernel's live clocksource selector, without a guest reboot
or software upgrade. This does not test boot-time selection or reboot persistence.

### Original authorized runtime entry point

Use the existing Kepler SSH alias (port 2222). The guest SSH options below match
`just verify-k3s-observability`'s private ephemeral-guest policy. Before changing
cp-1, verify cp-2 and cp-3 are Ready and both advertise
`etcd_server_has_leader 1` on port 2381. Verify their API `/readyz` with the
existing homelab kubeconfig and its CA; never use an insecure TLS bypass.

```sh
ssh -o BatchMode=yes -o ConnectTimeout=8 kepler '
  timeout 15 ssh -o BatchMode=yes -o ConnectTimeout=4 \
    -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null \
    root@10.250.0.11 "bash -s"
' <<'GUEST'
set -euo pipefail
selector=/sys/devices/system/clocksource/clocksource0
test "$(hostname)" = cp-1
test "$(cat "$selector/current_clocksource")" = tsc
grep -qw kvm-clock "$selector/available_clocksource"
printf '%s\n' kvm-clock > "$selector/current_clocksource"
test "$(cat "$selector/current_clocksource")" = kvm-clock
systemctl restart systemd-timesyncd.service
date -u
cat "$selector/current_clocksource"
GUEST
```

After live clocksource selection, require a fresh NTP synchronization sample.
The first observation found `NTPSynchronized=no`, with timesyncd active and its
poll interval at 34 minutes 8 seconds. Restart only cp-1's time-sync service to
reacquire synchronization; do not restart k3s or another guest.

Observe all three control planes for at least 15 minutes: compare guest wall
clock with the client and monotonic elapsed time, verify fresh cp-1 node leases,
API readiness, NTP synchronization, etcd leader availability/failed proposals,
and new kernel RCU/timer/clocksource errors. Record peer boot IDs to prove the
test did not restart cp-2 or cp-3. A short pass is initial evidence, not proof
the intermittent failure is fixed; continue normal workload observation.

### Original runtime rollback

If cp-1 regresses while reachable, use the same guest SSH transport to run:

```sh
printf '%s\n' tsc > /sys/devices/system/clocksource/clocksource0/current_clocksource
```

The runtime selection also resets on reboot because the declarative parameter
has not been deployed. A failed SSH connection is not permission to restart the
host or both remaining control planes. Persistent rollout requires reconciling
the deployed guest baseline first, then dry-building, inspecting guest closure
impact and deploying one control plane at a time with quorum gates. Source
rollback removes the cp-1-only `boot.kernelParams` line before that deployment.

### Original review and evidence

Security, reliability, compatibility and operations review: keep authentication
and kubeconfig CA verification; use the fixed cp-1 target and require its
hostname/current selector; preserve quorum and avoid unrelated K3s upgrades.
The isolated live selector is reversible and does not edit guest configuration
files. Scope evaluation must show the parameter only on cp-1. Kernel, lease and
API observations exercise real behavior rather than treating configuration
evaluation as proof of runtime recovery.

#### Execution receipt

- Task checkout: `worktrees/cp1-kvm-clock-canary-20261002`, branch
  `fix/cp1-kvm-clock-canary-20261002`, based on `9f150045`, uncommitted changes.
- At 13:02:52 UTC on October 2, cp-1 switched from `tsc` to `kvm-clock`.
  Its kernel recorded the selection; no guest or host reboot was performed.
- The first observation correctly failed the NTP synchronization check.
  Restarting only cp-1's timesyncd restored `NTPSynchronized=yes` with a fresh
  NTP sample. This is a protocol refinement, not evidence of an RCU recurrence.
- Sixteen successful samples from 13:07:34 through 13:22:21 UTC covered over
  15 minutes after NTP reacquisition and over 19 minutes after selection.
  Every control-plane API `/readyz` returned `ok`; all three had fresh node
  leases, synchronized NTP, an etcd leader and zero failed proposals.
- No new RCU stall, timer-wakeup or unstable-clocksource kernel message was
  found after the switch. cp-1's successive wall/monotonic elapsed-time
  differences remained within 0.075 seconds. These sequential measurements are
  coarse diagnostics, not a clock-accuracy benchmark.
- cp-2 and cp-3 stayed on `tsc`, with boot IDs unchanged from preflight:
  `02d2920a-583b-4446-9e39-3625e8393525` and
  `96349871-8388-4b18-ab84-c5a358049317`. cp-1's boot ID remained
  `cccc4643-02a2-4502-972e-57137bab15b8` throughout observation.

#### Original source validation and handoff

The scope assertion below failed before the configuration edit because cp-1
lacked the parameter, then passed after it. All other guests retain their
original parameter lists. Lint, formatting, documentation links, whitespace
checks and the offline Kepler toplevel dry-build passed. The dry-build evaluates
and enumerates work; it does not prove a realized closure or deployment.

```sh
nix eval --json --offline .#nixosConfigurations.kepler.config.microvm.vms \
  --apply 'vms: let params = builtins.mapAttrs (_: vm: vm.config.config.boot.kernelParams) vms; in assert builtins.elem "clocksource=kvm-clock" params.cp-1; assert builtins.all (name: name == "cp-1" || !(builtins.elem "clocksource=kvm-clock" params.${name})) (builtins.attrNames params); params'
```

The initial runtime experiment passed. Intermittent-failure attribution,
boot-time selection and persistence are still unproven. Leave the cp-1 runtime
canary in place for normal workload observation; it resets to `tsc` on reboot.
Reconcile the live/source version drift before any persistent deployment.
The compatibility review's broad-upgrade finding remains a deployment gate;
the reliability review's NTP refresh finding was applied and verified.

## Phased persistent rollout

The operator subsequently requested “migrate all other in phases. Including
workers. Lets make change persistent via desktop-nixos” and explicitly authorized
the checkout's guest updates, including K3s 1.35.7 to 1.36.4. The source now sets
`clocksource=kvm-clock` for every Kepler cluster guest and
`microvm.vms.<name>.restartIfChanged = false`. Host activation prepares the
declarative runners without intentionally restarting the running guests; each
guest must then be restarted individually. The earlier cp-1-only evidence above
is preserved as the first phase, not rewritten as all-guest acceptance.

The source and running host kernel both resolve to the same Linux 7.2.3 store
path. Inspect the host activation preview before using live activation; any
storage, networking or driver change that breaks the single-guest rollout is a
stop gate. Boot-only staging followed by a host reboot cannot substitute for
this phased rollout.

Orion is unavailable as a builder; the operator explicitly selected Apollo or
Kepler instead. Use Apollo so the deployment target does not compile its own
closure. The following documented variant uses the
same pinned deploy-rs output and activation flags as the owner recipes, with
Apollo builds and the working Kepler SSH alias:

```sh
# Build, transfer and preview only; inspect changes before live activation.
builders="ssh-ng://erik@apollo:2222 x86_64-linux /home/erik/.ssh/id_ed25519 2 1 big-parallel,benchmark,kvm,nixos-test"
nix run .#deploy-rs -- --skip-checks --dry-activate --hostname kepler .#kepler \
  -- --option builders "$builders" --option builders-use-substitutes true --max-jobs 0
# Only after the preview and preflight gates pass:
nix run .#deploy-rs -- --skip-checks --hostname kepler .#kepler \
  -- --option builders "$builders" --option builders-use-substitutes true --max-jobs 0
```

If the local daemon cannot use Apollo's existing user SSH trust, transfer the
evaluated activation derivation and build directly through that trusted user
connection. This builds the same closure without changing host-key policy:

```sh
drv=$(nix eval --raw .#deploy.nodes.kepler.profiles.system.path.drvPath)
nix copy --derivation --option substituters https://cache.nixos.org --to ssh-ng://erik@apollo:2222 "$drv"
ssh apollo "nix build --no-link '$drv^*' --option substituters https://cache.nixos.org --option builders '' --max-jobs 2"
out=$(nix eval --raw .#deploy.nodes.kepler.profiles.system.path.outPath)
nix copy --no-check-sigs --substitute-on-destination --option substituters https://cache.nixos.org --from ssh-ng://erik@apollo:2222 "$out"
nix run .#deploy-rs -- --skip-checks --dry-activate --hostname kepler .#kepler \
  -- --option substituters https://cache.nixos.org --option builders '' --max-jobs 0
```

Before activation, record all six boot IDs, runners, readiness, K3s versions and
workload health. After activation, require every guest boot ID to be unchanged
before entering the restart phases. Verify host SSH, storage mounts and existing
workloads; retain the previous host generation for rollback.

Restart order is `cp-1`, `cp-2`, `cp-3`, `w-1`, `w-2`, `w-3`. Before each control
plane, require the other two healthy APIs and an etcd leader. Drain each target
using the existing homelab kubeconfig, honor PodDisruptionBudgets and stop if
eviction fails; do not force-delete pods or override budgets. Restart only its
`microvm@<name>.service` through Kepler. Wait for a changed boot ID, a Ready node,
boot command line containing `clocksource=kvm-clock`, the active `kvm-clock`
selector, synchronized NTP, fresh lease and running K3s. Verify the new version,
peer APIs and etcd quorum, then uncordon. Observe clock/heartbeat health and
workload recovery before advancing. A guest boot into the new parameter tests
persistence; a source evaluation alone does not.

If any phase regresses, stop rollout, preserve the healthy peers and inspect
that node. Live-selector rollback remains available. A K3s binary downgrade
after an etcd migration is not an automatic safe rollback: retain the previous
runner and take a current etcd snapshot before the first server upgrade.

This page is the task's review one-pager and operational handoff; no commit,
push or human approval is implied.

### Activation preview decision

Apollo built the evaluated closure successfully. The initial dry activation explicitly
preserved all microvm and virtiofs units, but restarted host networking, Tailscale,
NFS and ZFS services. The operator selected **Proceed with host activation**
after being shown that interruption. Proceed with the same pinned deploy-rs
command above, using the already built closure (`builders=''`, `max-jobs=0`),
then compare all six boot IDs before the individual guest phases. The temporary
copy signature exception applies only to our evaluated source-built closure
from the authenticated Apollo connection; no trust configuration is changed.

Take the pre-upgrade etcd snapshot on cp-3 with
`k3s etcd-snapshot save --name pre-clocksource-20261002`; verify its listing
before the first server upgrade.

Before any guest software upgrade, if activation stops the fleet, restore
the recorded prior host closure using its `bin/switch-to-configuration switch`,
then start `microvms.target` and the control-plane guests individually. Do not
advance guest upgrades until the old cluster is recovered. The prior closure for
this run is `/nix/store/nzak8g9vk5jm5c3sxnlwq0w47jk9gxp3-nixos-system-kepler-26.11.20260902.3ed67ec`.
Restore the system profile with `nix-env --profile /nix/var/nix/profiles/system
--set <prior-closure>` and run that closure's `bin/switch-to-configuration boot`
as root as well, so the rejected generation cannot activate on the next reboot.
This procedure was used for the first failed activation only. After the second
activation upgraded the guests and etcd, that old host/guest generation is not
an automatic safe rollback; preserve current guest data and plan recovery.

### First activation failure and corrected dependency gate

The first live activation stopped all six guests through required bootstrap
services and stalled waiting for Harbor credentials. No guest upgrade occurred.
The prior host closure and boot profile were restored; all six nodes recovered
on K3s 1.35.7 and all 27 Argo applications were Synced/Healthy. This interruption
also reset the runtime cp-1 clock canary. The initial preview was insufficient:
preserving VM units alone does not prevent dependency-triggered stops.

The corrected source also sets `restartIfChanged=false` on `harbor-reader`,
`k3s-bootstrap-materialize` and `k3s-cluster-token`. A targeted evaluation
assertion failed before that fix and passed afterward. Apollo rebuilt the
closure. The second dry activation explicitly lists those three services and
all VM/tap/virtiofs units as **would NOT stop**. Capture a fresh boot-ID baseline
and retry activation only with that closure; require unchanged guest boot IDs
before any individual restart. Deferred bootstrap-service changes take effect
at the next host boot. Post-upgrade recovery must preserve migrated guest data;
do not automatically revert upgraded etcd members to older guest runners.

### Second activation: persistence achieved, phased gate failed

The second activation also restarted all six guests. The host journal at
2026-10-02 16:48:03 UTC records ZFS import-service stops, mount unmount attempts
and concurrent guest stops. `fast.mount` requires
`zfs-import-fast-pool.service`; guest and virtiofs units require `fast.mount`.
Thus preserving VM and bootstrap units was still insufficient. Worker shutdowns
timed out before the new guests started. The stop list must include transitive
mount prerequisites, not only the guest units.

All six guests subsequently booted the intended new runners with
`clocksource=kvm-clock`, selected that clock, synchronized NTP and became Ready
on K3s 1.36.4. All three API readiness checks passed and each etcd member had a
leader with zero failed proposals. The requested one-at-a-time migration was
**not achieved**. Do not roll back upgraded etcd members merely to replay the
phases or claim the failed boot-ID gate passed.

The final correction preserves both ZFS pool-import services across switches.
The targeted assertion failed before the fix. Run
`bash scripts/check-k3s-clock-rollout.sh` to check all guest parameters and the
five shared service guards. Apollo built this correction; its dry activation
lists only the two ZFS import units as **would NOT stop**, plus a Home Manager
restart. Apply this narrow correction using the documented pinned deploy-rs
command, compare all guest boot IDs again, and observe clocks and workloads.

### Final execution receipt and review handoff

- Apollo built the final closure. Pinned deploy-rs reported **Deployment
  confirmed** for `8yb0444cdaqzxq3y94xbxapbmlzgbnhl-activatable-nixos-system-kepler-26.11.20260922.6774f7b`.
  `/run/current-system` points to the corresponding `l400ajs...` host closure;
  the system boot profile points to the confirmed activation closure.
- All six guest `current` and `booted` runner links match the new evaluated
  runners. Their boot command lines contain `clocksource=kvm-clock`, selectors
  report `kvm-clock`, NTP is synchronized, and K3s reports `v1.36.4+k3s1`.
  Guest reboot persistence is observed; a full host reboot has not been tested.
- The final guard-only activation preserved every guest boot ID. The control
  planes and workers were already running the new configuration for over four
  hours when final observation began.
- Four successful sequential samples from 21:25:15 through 21:29:36 UTC checked
  all six unchanged boot IDs, wall-clock alignment, wall/monotonic elapsed-time
  agreement, NTP, boot parameters, Ready status and fresh leases. Maximum
  sampled lease age was 10.2 seconds. No current-boot kernel RCU stall,
  starved-kthread, timer-wakeup or unstable-clocksource message was found.
- All three authenticated API readiness checks passed and all etcd members
  retained a leader. The first strict zero-failure check correctly failed:
  cp-1 had four accumulated failed proposals. The bounded follow-up checked
  counter growth, not zero history; cp-1 stayed at four and cp-2/cp-3 at zero
  throughout all four samples. Attribution of those four failures remains open;
  a growing counter, lost quorum or recurring clock/RCU fault warrants follow-up.
- All 27 Argo applications recovered to Synced/Healthy, including Langfuse.
  Kepler had no failed system services and both ZFS pools reported healthy.

Final review applied security, reliability, compatibility and operations
perspectives directly: credential/CA verification stayed intact; bootstrap and
mount stop propagation were traced in actual systemd dependencies; guest
binary downgrades were avoided after the upgrade; failed phase gates and the
nonzero proposal counter are retained rather than relabeled as passes. The
durable evaluation check covers exactly six guests, guest-only kernel scope and
all five shared service guards. It checks configuration, not runtime health.
Run it with lint, formatting, the Kepler toplevel dry-build, documentation links
and whitespace checks before landing this task branch. The subsequent human
request authorizes merging this change into main, then investigating proposal
failures and exercising controlled single-node activation. Long-term failure
attribution remains unproven.

Final validation passed: rollout evaluation assertions, shell syntax, Statix
lint, Alejandra formatting, offline Kepler toplevel dry-build, documentation
links and whitespace. A fresh post-validation cluster read again showed all six
nodes Ready and all 27 applications Synced/Healthy.

## Post-merge investigation and controlled worker update

The operator requested merging to main, then extended observation and a real
single-node update. PR #366 merged as `f9e1f1f` on October 2 at 23:31 UTC.
Four additional successful samples from 23:32:42 through 23:36:49 UTC preserved
all guest boot IDs, synchronized clocks, fresh leases, API readiness and quorum.
The failed-proposal counters remained cp-1=4, cp-2=0, cp-3=0.

All three journals show startup hash-check timeouts while peers were returning
at 16:51 UTC, then an etcd leader election at 16:51:47 UTC. That pre-drill
inspection found no later etcd leader loss. Slow apply/read-index warnings occur on all three peers, not only
cp-1. These facts do not uniquely attribute the four failed proposals. Historical
proposal counters were unavailable: Alloy's etcd keep filter omitted `_total`
from the applied, committed and failed metric names. The owner fix belongs to
`homelab-gitops`, with a regression check against the exported metric names.

Use w-3 for the controlled update. Temporarily add the NixOS provenance tag
`clock-rollout-canary` to that guest only; it changes its closure without changing
its K3s version, clock policy or workload configuration. Evaluate and require
all other guest runners to match the live runners. Build on Apollo and inspect
the pinned deploy-rs preview using the commands above. Capture all six boot IDs
before host activation; require that staging changes none of them.

After staging, drain w-3 through the existing homelab kubeconfig, honoring PDBs:
`kubectl --context homelab drain w-3 --ignore-daemonsets --delete-emptydir-data
--timeout=5m`. When local routing cannot reach the cluster, stream that context's
existing configuration to Kepler's kubectl as in the prior verification.
If eviction fails, uncordon and stop the test. Otherwise run only
`sudo systemctl restart microvm@w-3.service` on Kepler, matching the owner worker
restart recipe. Require w-3's boot ID to change, its new tagged closure to run,
and the other five boot IDs to stay unchanged. Verify Ready, kvm-clock, NTP,
K3s 1.36.4, fresh leases and all control-plane APIs/quorum, then uncordon w-3
and verify workload recovery. Remove the temporary source tag, rebuild/restage,
and repeat the same bounded worker procedure to restore the untagged desired closure.
No control-plane guest or physical host reboot is part of this drill.

### Worker drill incident and restoration gate

The first drill activated the genuinely new tagged w-3 closure. Staging preserved
all six boot IDs; draining honored PDBs and only w-3's VM rebooted. All six nodes
and all 27 applications recovered by October 3 at 00:07 UTC. However, cp-1's K3s
process exited at 00:02:10 UTC and restarted automatically, without a VM reboot.
Its controller, scheduler and cloud-controller leader leases timed out after
etcd read-index delays and an 8.87-second apply. The checked kernel logs showed
no accompanying OOM, RCU or clocksource fault. This is a failed control-plane
service-continuity gate, despite successful single-VM activation isolation.

The proposal counters changed from 4/0/0 to 0/4/3: cp-1's counter reset with its
process; cp-2 and cp-3 accumulated failures. Do not treat that reset as recovery
of the earlier four failures. WAL fsync p99 over the incident's five-minute
window was 119–134 ms, and backend commit p99 was 135–293 ms. A later sample was
29–31 ms and 32–42 ms respectively. The exact writer and cause of the 8.87-second
delay remain unproven; all control planes share fast-pool with the workers.

Remove the temporary source tag and stage the original worker closure first,
requiring unchanged guest boot IDs and healthy control-plane APIs. Before the
restoration restart, capture K3s process restart counts and failed-proposal
counters as well as VM boot IDs. Evict w-3's non-DaemonSet pods **serially** through
the native policy/v1 Eviction API, respecting PDB denials and ordinary grace
periods, with a ten-second interval between evictions. Stop and uncordon on a
control-plane restart, increased proposal counter or loss of readiness/quorum.
After the worker-only restart, verify the untagged running closure and unchanged
peer boot IDs/process restart counts, then observe workload recovery. This
reduces eviction concurrency; it does not remediate the shared storage domain.

### Serial restoration and monitoring receipt — October 3

- The monitoring filter and its regression check merged in
  [homelab-gitops PR #163](https://github.com/ErikBPF/homelab-gitops/pull/163)
  as `e72e226f`. Required CI passed after correcting two stale test expectations
  to match existing Karakeep and Wazuh storage declarations; no workload storage
  declaration changed. The owner sync command deployed that reviewed revision
  to `alloy-metrics`. Prometheus now exports proposal totals for all three
  control planes; failed totals are 0/4/3. Earlier dropped history is unavailable.
- Removed the temporary w-3 provenance tag from source. Apollo built the
  untagged closure; copying it back used authenticated `ssh://erik@apollo:2222`
  after `ssh-ng` transfers stalled. Pinned deploy-rs confirmed the staged host
  activation, and the repeated staging gate preserved all six guest boot IDs.
- Serially evicted twelve managed non-DaemonSet pods through policy/v1,
  with UID preconditions, ordinary grace periods, PDB enforcement, ten-second
  intervals and control-plane continuity checks between evictions. Only
  `microvm@w-3.service` was restarted. w-3 returned Ready and was uncordoned;
  its K3s service became active at 00:52:20 UTC with no automatic restarts.
- The running w-3 closure is the intended untagged
  `db17i3fplclp06h6csfv55indcm227kj-nixos-system-w-3-26.11pre-git`.
  Its boot ID changed from `97750ae6-5b32-4265-a719-036ba6aa0249` to
  `0cae16bd-ca04-4863-a91a-17a2c615d912`; every other guest boot ID stayed unchanged.
  Control-plane K3s restart counts remained 1/0/0, and proposal failures remained
  0/4/3 throughout the serial evictions, restart and recovery.
- The orchestration command exceeded its fifteen-minute terminal deadline while
  awaiting Langfuse, after the worker was already uncordoned. This timeout is
  not a passed workload gate. Independent follow-up observed ClickHouse finish
  its volume-permission traversal and start at 00:59:01 UTC; the Langfuse worker
  recovered from registry HTTP 429 backoff at 01:01:08 UTC. No forced pod deletion,
  permissions bypass or registry-policy change was used to obtain recovery.
- Four successful observation samples from 01:02:50 through 01:07:14 UTC checked
  all six stable boot IDs, persistent `kvm-clock`, synchronized/aligned clocks,
  wall/monotonic agreement, Ready status and fresh leases. Maximum sampled lease
  age was 9.6 seconds. No current-boot RCU stall, timer-wakeup or unstable-clock
  message was found. All three authenticated APIs and etcd quorum remained
  healthy, with unchanged K3s restart and failed-proposal counters.
- Independent final verification passed the control-plane continuity assertion,
  all six Ready nodes and all 27 Argo applications Synced/Healthy. The temporary
  tag is absent from desired source and the running worker. This proves the
  bounded **worker-only** closure transition and serial restoration; it does not
  validate a control-plane version upgrade or full Kepler reboot.

The first concurrent drain's K3s process failure remains a real incident, not a
clocksource-test pass. Its immediate mechanism was controller leader-lease
timeouts following etcd delays. Shared fast-pool contention is a supported
investigation direction, not an attributed writer or a completed storage fix.
Any further maintenance should retain VM boot-ID, K3s restart-count, proposal
counter, API/quorum and workload gates, and allow for stateful startup time.
