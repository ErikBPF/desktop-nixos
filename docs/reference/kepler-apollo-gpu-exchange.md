# Kepler / Apollo GPU exchange

**Status:** GPUs exchanged; host, storage, network and bounded Apollo compute acceptance passed. Three-entry boot retention applied; household inference remains paused.

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
physical clearance or PSU suitability. This inventory predates the exchange.
Neither host has `lspci` installed; sysfs provided the inventory above.

The Radeon is not accepted as an equivalent CUDA inference replacement.
Kepler's pre-exchange source included NVIDIA initrd/kernel modules, driver/toolkit,
persistence, `nvtopPackages.nvidia`, and a 170 W / 210–1500 MHz clock-limiting
unit. That policy documents prior Xid 13/31 faults. Moving the card does not
repair it: preserve those limits on Apollo until a bounded workload test proves
stability. Do not relax them as part of the exchange.

## Manual acceptance and implementation seams

[GPU exchange behavior contract](../behaviors/kepler-apollo-gpu-exchange/exchange.feature)
is deliberately unautomated. Source preparation belongs here; workload/image and
endpoint changes belong to Servarr, with IaC owning any required network policy.
The coordination decision is maintained in Homelab's Orion/Apollo stability
proposal. Both hosts have booted the exchanged-driver configurations; Kepler
passed acceptance, while Apollo requires the linked NIC recovery.

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

During this pause IaC withdraws `ha-agent-qwen4b` and Servarr removes its expected
probe entry. Discovery's semantic canary checks the still-promised `qwen-chat`
route through an actual completion and database readiness; failure alerts remain
enabled. Credentials, model data and Compose definitions stay intact. Restoring
the HA alias requires explicit workload placement and a verified backend first.

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

For the initial exchange, each host was staged once from the reviewed revision.
Kepler retained two boot entries; Apollo temporarily kept all existing
generations. Recheck retained entries after every staging attempt.

Apollo's profile ledger advanced from generation 12 to 13 during preparation,
while the running original remains generation 8. The bootloader applies its
retention limit to profile generations before skipping unusable wrappers.
Apollo's limit was temporarily set to `null` (keep all), preserving the original
AMD recovery entry through the exchange. Hardware and networking acceptance
now permit restoring three entries as described in the compute acceptance below.

## Bounded Apollo compute acceptance

Read the available tools and idle GPU before choosing a correctness workload:

```bash
ssh -p 2222 -o BatchMode=yes -o ConnectTimeout=8 erik@192.168.10.174 \
  'command -v python3 nvcc nvidia-smi podman docker || true
   nvidia-smi --query-gpu=name,temperature.gpu,power.limit,power.draw,memory.used --format=csv,noheader
   nvidia-smi --query-compute-apps=pid,process_name,used_memory --format=csv,noheader
   podman images --format "{{.Repository}}:{{.Tag}}"'
```

Keep the existing 170 W / 210–1500 MHz limits. Do not resume household
inference or borrow an active application's container for this check.

Build only NVIDIA's pinned CUDA 12.8 `matrixMul` sample, which checks every
result against its known constant-input reference. Its source comes from the
flake's CUDA sample derivation; no application data or custom GPU kernel is used:

```bash
sample=$(nix build --impure --no-link --print-out-paths --expr '
  let f = builtins.getFlake (toString ./.);
      sample = f.nixosConfigurations.apollo.pkgs.cudaPackages.cuda-samples;
  in sample.overrideAttrs (old: {
    pname = "apollo-matrixmul"; name = "apollo-matrixmul-12.8";
    prePatch = ""; postPatch = "";
    nativeBuildInputs = builtins.filter (p: (p.pname or "") != "cmake") old.nativeBuildInputs;
    buildInputs = builtins.filter (p: builtins.elem (p.pname or "")
      [ "cuda_cudart" "cuda_cccl" "cuda_profiler_api" ]) old.buildInputs;
    dontUseCmakeConfigure = true;
    buildPhase = "nvcc -O2 -arch=sm_86 -ICommon Samples/0_Introduction/matrixMul/matrixMul.cu -o matrixMul";
    installPhase = "install -Dm755 matrixMul $out/bin/matrixMul; install -Dm644 LICENSE $out/share/licenses/cuda-samples/LICENSE";
  })')
# All runtime dependencies are already present on Apollo; import only this local build.
nix-store --export "$sample" | ssh -p 2222 -o BatchMode=yes erik@192.168.10.174 \
  'sudo -n nix-store --import'
```

The following bounded test uses the resulting immutable store path. Check it
matches the build output. It stops on errors or 85°C, uses a 65-second outer
timeout, and leaves host configuration and the retained GPU limits unchanged:

```bash
ssh -p 2222 -o BatchMode=yes -o ConnectTimeout=8 erik@192.168.10.174 'bash -s' <<'REMOTE'
set -euo pipefail
sample=/nix/store/x1g93y34041jipmny7w0jsccibm6vf8c-apollo-matrixmul-12.8/bin/matrixMul
test -x "$sample"
test -z "$(nvidia-smi --query-compute-apps=pid --format=csv,noheader)"
test "$(nvidia-smi --query-gpu=power.limit --format=csv,noheader,nounits)" = 170.00
systemctl is-active --quiet nvidia-conservative-clocks.service
start=$(date --iso-8601=seconds)
nvidia-smi --query-gpu=temperature.gpu,power.draw,clocks.gr,memory.used --format=csv,noheader
timeout --kill-after=5s 65s bash -c '
  set -e
  passes=0
  while (( SECONDS < 45 )); do
    "$1" -wA=2048 -hA=2048 -wB=2048 -hB=2048
    passes=$((passes + 1))
  done
  printf "completed_correctness_passes=%s elapsed_seconds=%s\n" "$passes" "$SECONDS"
' bash "$sample" &
load_pid=$!
trap 'kill -TERM "$load_pid" 2>/dev/null || true' EXIT
while kill -0 "$load_pid" 2>/dev/null; do
  temperature=$(timeout 5s nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits)
  test "$temperature" -lt 85
  nvidia-smi --query-gpu=timestamp,temperature.gpu,power.draw,clocks.gr,utilization.gpu --format=csv,noheader
  sleep 1
done
wait "$load_pid"
trap - EXIT
faults=$(journalctl -b -k --since "$start" --no-pager | grep -Ei 'NVRM.*Xid|GPU has fallen off|GPU.*fault' || true)
test -z "$faults" || { printf '%s\n' "$faults"; exit 1; }
nvidia-smi --query-gpu=temperature.gpu,power.limit,power.draw,memory.used --format=csv,noheader
nvidia-smi --query-compute-apps=pid,process_name,used_memory --format=csv,noheader
printf 'bounded_cuda_correctness=PASS new_gpu_faults=0\n'
REMOTE
```

This is bounded FP32 compute/memory-path evidence, not a repair of the card's
historical Xid faults or acceptance of Whisper, tensor-core inference, or an
extended thermal soak. Retain the conservative power and clock settings.

Observed **2026-09-07 21:08:40–21:09:28 UTC**: all eleven 2048×2048 runs
passed the upstream correctness check (300 timed multiplies per run), exit 0.
Forty-six telemetry samples peaked at 54°C and 76.51 W; active compute used
1500 MHz. No new kernel GPU fault appeared. The GPU returned to 1 MiB used
memory with no compute processes; its 170 W limit remained applied.

After this acceptance, restore Apollo's former three-entry boot limit. Run the
existing effective GPU contract, standard checks, `just dry apollo` and
`just build apollo`; merge after green CI, then `just deploy-rs-boot apollo`.
Before and after staging, use the recorded boot inventory above to verify the
running generation is unchanged and at least one accepted NVIDIA plus `lan0`
generation remains selectable. No extra reboot is needed for this cleanup.

Observed **2026-09-07 21:20:53 UTC** after [Desktop #301](https://github.com/ErikBPF/desktop-nixos/pull/301)
merged as `3dd1002` and `just deploy-rs-boot apollo` succeeded: exactly
generations **15, 16 and 17** remain selectable, with **17** the next-boot
default. Accepted generation **15** remains running; its exact `7.2.3` kernel
image is unchanged. ESP usage fell from 552 MiB to 210 MiB (1.8 GiB free).
Both NFS shares remain mounted, no system units failed, and the NVIDIA power
limit remains 170 W. This cleanup performed no reboot or inference restart.
