# Kepler / Apollo GPU exchange

**Status:** Inventory and migration preparation; hardware exchange not performed.

The operator selected removal of NVIDIA from Kepler by exchanging its GPU with
Apollo. Household inference is explicitly suspended for now. Physical compatibility
and a staffed shutdown window precede activating replacement hardware
configurations; future inference placement is separate.

## Read-only inventory

These commands use fleet.json addresses and read PCI device/driver identity only.
They do not install packages, stop workloads, load drivers or alter hardware.

```bash
for host in kepler apollo; do
  ip=$(jq -er --arg host "$host" '.hosts[$host].ip' fleet.json)
  printf '%s\n' "$host"
  ssh -p 2222 -o BatchMode=yes -o ConnectTimeout=8 "erik@$ip" \
    'for device in /sys/bus/pci/devices/*; do
      case "$(cat "$device/class")" in
        0x03*) printf "%s vendor=%s device=%s driver=%s\n" \
          "${device##*/}" "$(cat "$device/vendor")" "$(cat "$device/device")" \
          "$(basename "$(readlink "$device/driver")")" ;;
      esac
    done'
done
```

Kepler owns storage and the home k3s substrate. GPU retirement must not enable
its unattended upgrades, alter its kernel hold, migrate disks or change VM
placement. Apollo remains the work development host; accepting a GPU does not
implicitly authorize moving household inference there.

## Observed inventory — 2026-09-07

| Host | PCI identity | Current driver | Selected destination |
|---|---|---|---|
| Kepler | `0000:06:00.0`, `10de:2488`; RTX 3070 LHR in the owning hardware module | `nvidia` | Apollo |
| Apollo | `0000:03:00.0`, `1002:665f`; Tobago PRO / Radeon R7 360 or R9 360 OEM family | `amdgpu` | Kepler |

The [pciutils ID database](https://kernel.googlesource.com/pub/scm/utils/pciutils/pciutils/+/7078ff5329bc467d32d41dc91667a8cfd871e767/pci.ids)
identifies the AMD family; PCI ID alone does not prove board variant, VRAM,
physical clearance or PSU suitability. The cards have not been exchanged.
Neither host has `lspci` installed; sysfs provided the inventory above.

The Radeon is not accepted as an equivalent CUDA inference replacement.
Kepler's current source includes NVIDIA initrd/kernel modules, driver/toolkit,
persistence, `nvtopPackages.nvidia`, and a 170 W / 210–1500 MHz clock-limiting
unit. That policy documents prior Xid 13/31 faults. Moving the card does not
repair it: preserve those limits on Apollo until a bounded workload test proves
stability. Do not relax them as part of the exchange.

## Manual acceptance and implementation seams

[GPU exchange behavior contract](../behaviors/kepler-apollo-gpu-exchange/exchange.feature)
is deliberately unautomated. Source preparation belongs here; workload/image and
endpoint changes belong to Servarr, with IaC owning any required network policy.
The coordination decision is maintained in Homelab's Orion/Apollo stability
proposal. The reviewed candidate changes both host driver configurations; the running
host generations remain unchanged until the physical exchange.

1. Keep household inference suspended as selected; record future workload
   placement before drafting resume/service/route changes.
   Existing Kepler HA, embedding/reranking and experiment configurations include
   NVIDIA dependencies; static files alone do not establish current consumers.
2. Prepare an isolated, reviewed host revision: remove Kepler-only NVIDIA
   modules/toolkit/clock unit and enable its observed AMD driver; add the current
   NVIDIA policy to Apollo. Reuse host hardware modules, not a new abstraction.
   Preserve Kepler storage, kernel hold and all VM placement.
3. Verify actual evaluated host options, lint/format, `just dry kepler` and
   `just dry apollo`. Require expected-driver and no-NVIDIA-on-Kepler checks;
   source-string searches alone cannot prove effective module composition.
   Retain compatible boot generations for both the current and swapped hardware.
4. Before shutdown, verify physical slot/PSU/cabling, console access, current
   backups, explicit workload stop/start ownership and the Kepler cold-start
   contract. Do not turn a GPU exchange into an unreviewed host upgrade.
5. In a staffed window, stop dependent work through owner recipes, shut both
   hosts down cleanly, physically exchange cards, then boot the prepared
   generations. A person must perform and confirm the physical operation.
6. Re-run the inventory; verify driver binding, SSH, Kepler storage/k3s and
   Apollo's five-node substrate. Then verify selected model routes/telemetry and
   bounded NVIDIA stability under retained limits. An OS boot is not inference
   acceptance. Keep alerts truthful until their actual conditions recover.
7. If hardware binding, storage or service acceptance fails, stop later work.
   Use the pre-recorded compatible generation and original physical layout in
   the staffed recovery procedure; do not improvise a remote blind rollback.

## Household inference suspension — selected 2026-09-07

The operator selected commenting out household inference for now, so no
household service is automatically relocated to Apollo. Keep model data and
Compose definitions. Kepler's declared stack list excludes `whisper-gpu`,
`qwen4b-gpu`, and `retrieval` during the exchange.

Read current units, container names and NVIDIA consumers before stopping them:

```bash
ssh -p 2222 -o BatchMode=yes -o ConnectTimeout=8 erik@192.168.10.230 \
  'export XDG_RUNTIME_DIR=/run/user/$(id -u)
   systemctl --user show podman-compose-whisper-gpu.service podman-compose-qwen4b-gpu.service podman-compose-retrieval.service -p Id -p LoadState -p ActiveState -p SubState
   podman ps --format json | jq "map({name:.Names[0],state:.State})"
   nvidia-smi --query-compute-apps=pid,process_name,used_memory --format=csv,noheader'
```

Stop only the declared household units after inventory confirms their identity;
no volume deletion, model deletion or blanket container stop. Active experiment
processes must finish or be explicitly stopped through their owner before the
physical shutdown; commenting household stacks does not prove the GPU is idle.

Authorized suspension for the observed active retrieval stack:

```bash
ssh -p 2222 -o BatchMode=yes -o ConnectTimeout=8 erik@192.168.10.230 \
  'export XDG_RUNTIME_DIR=/run/user/$(id -u)
   systemctl --user show podman-compose-retrieval.service -p ExecStop'
ssh -p 2222 -o BatchMode=yes -o ConnectTimeout=8 erik@192.168.10.230 \
  'export XDG_RUNTIME_DIR=/run/user/$(id -u)
   systemctl --user stop podman-compose-retrieval.service
   systemctl --user show podman-compose-retrieval.service -p ActiveState -p SubState
   nvidia-smi --query-compute-apps=pid,process_name,used_memory --format=csv,noheader'
```

Observed suspension: Whisper and Qwen user units were absent/inactive. Retrieval
was active with only the two BGE containers consuming CUDA. Its existing
`ExecStop` uses Compose `stop` (no removal or volume flags). Stopping that unit
returned inactive/dead; the NVIDIA compute-process query returned no rows.
Model definitions, model files, databases and backup containers were retained.

## Boot-only staging

Before staging, record running/profile generations and upgrade activity:

```bash
for host in kepler apollo; do
  ip=$(jq -er --arg host "$host" '.hosts[$host].ip' fleet.json)
  printf '%s\n' "$host"
  ssh -p 2222 -o BatchMode=yes -o ConnectTimeout=8 "erik@$ip" \
    'readlink -f /run/current-system
     readlink -f /nix/var/nix/profiles/system
     uname -r
     readlink -f /run/current-system/kernel
     readlink -f /run/booted-system/kernel
     sudo nix-env -p /nix/var/nix/profiles/system --list-generations
     df -h /boot
     sudo bootctl list --no-pager
     systemctl show nixos-upgrade.timer nixos-upgrade.service -p Id -p LoadState -p ActiveState -p SubState'
done
```

Observed preflight: both hosts run kernel `7.2.3`, with kernel image
`/nix/store/4f2m1k8c5ih0fa6zh8762k4s6pa6bw0p-linux-7.2.3/bzImage`.
Kepler's six guests run `7.2.3`; Apollo's five guests run `6.18.49`.
The main-branch package input would downgrade these kernels. Preserve this
running baseline through a scoped pinned kernel input, without importing the
unrelated changes in the canonical checkout's dirty lock file.

Recorded compatible host generations before staging:

| Host | Running system | Compatible boot entry | ESP free |
|---|---|---|---|
| Kepler | `/nix/store/y2wwlynrdvlk29iy7falw6866agrhfrc-nixos-system-kepler-26.11.20260905.c043004` | Generation 126 | 1.7 GiB |
| Apollo | `/nix/store/z9h08r55cs8f7rx2l882x2xnxcphpjb1-nixos-system-apollo-26.11.20260905.c043004` | Generation 8 | 1.9 GiB |

Both upgrade timers/services were absent and inactive. Apollo's existing
next-boot profile differed from its running system; do not treat a profile
symlink alone as evidence of what is running. Retain the compatible entries
above when staging and verify their presence again afterward.

After reviewed CI and both actual host builds pass, stage through the existing
owner recipe, without a live switch or reboot:

```bash
just deploy-rs-boot kepler
just deploy-rs-boot apollo
```

Verify both profile/default boot targets refer to the reviewed exchanged-driver
generations while `/run/current-system` remains the recorded original. Do not
signal ready-to-move if either staging failed or an upgrade is running. Keep
both hosts powered normally until the operator is ready to shut both down and
perform the exchange. Never remove a powered card.

Read actual running VM kernel arguments through the trusted owning host:

```bash
for host in kepler apollo; do
  ip=$(jq -er --arg host "$host" '.hosts[$host].ip' fleet.json)
  ssh -p 2222 -o BatchMode=yes -o ConnectTimeout=8 "erik@$ip" 'bash -s' <<'REMOTE'
set -eu
if [ "$(hostname)" = kepler ]; then
  state=/fast/microvms
  names="cp-1 cp-2 cp-3 w-1 w-2 w-3"
else
  state=/var/lib/microvms
  names="cp-1 cp-2 cp-3 w-1 w-2"
fi
for name in $names; do
  printf '%s %s\n' "$(hostname)" "$name"
  readlink -e "$state/$name/booted" "$state/$name/current" "$state/$name/toplevel"
  pid=$(systemctl show "microvm@$name.service" -p MainPID --value)
  test "$pid" -gt 0
  sudo awk -v RS='\0' 'prev=="-kernel" || prev=="--kernel" {print "kernel=" $0} prev=="-initrd" || prev=="--initramfs" {print "initrd=" $0} {prev=$0}' "/proc/$pid/cmdline"
done
REMOTE
done
```

Observed all eleven running VM processes: Kepler uses
`/nix/store/5pfk37ynwny49qfmb7s0sy57d8jqvih3-linux-7.2.3-dev/vmlinux`;
Apollo uses `/nix/store/8gsy6nldplfw12ylblabahhay8bv8xfx-linux-6.18.49-dev/vmlinux`.
Every VM's `booted` and `current` runner matched. Use these exact paths when
checking the prepared kernels. Boot-only staging leaves running VMs alone;
the next host boot installs the declared guest runners before starting them.

Stage each host once from the final reviewed revision. Kepler retains two boot
entries; Apollo temporarily keeps all existing generations: a second distinct staged revision could evict the
original Kepler generation. Recheck retained entries after every staging attempt.

Apollo's profile ledger advanced from generation 12 to 13 during preparation,
while the running original remains generation 8. The bootloader applies its
retention limit to profile generations before skipping unusable wrappers.
Temporarily set Apollo's limit to `null` (keep all), so other authorized staging
cannot consume its original AMD recovery entry. Check ESP space and confirm
that generation 8 remains selectable after staging. Restore a finite limit
only after the exchanged hardware has passed acceptance.
