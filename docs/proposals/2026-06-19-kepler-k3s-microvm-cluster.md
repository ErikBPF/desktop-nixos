# k3s test cluster on `kepler` via microvm.nix

**Date:** 2026-06-19
**Status:** Proposal — grilled twice (§10, §10b: round 2 simplified the LB design
— kepler-as-L4-LB drops kube-vip + MetalLB). Core decisions locked; NixOS-native
distro survey added (§12). Remaining opens are implementation details
(§6 "Still open"); ready for module work.
**Owner:** erik
**Target host:** `kepler` (existing) — adds a VM-hosted k3s cluster aspect
**Related:** microvm.nix (currently a *transitive* dep via `hermes-flake`, to be
promoted to a direct input); NixOS `services.k3s` module; libvirt precedent on
`discovery` (HAOS) — deliberately *not* reused here.

> Scope framing: this is a **local test/playground cluster** for trying
> Kubernetes tooling. Not production, not exposed off-LAN. "Built well, not
> undersized" (128 GB host) — realistic multi-node, but disposable by design.
>
> **Thesis (after the framework study, §5.9): a *NixOS-native* cluster** —
> infra, k3s, *and* the platform baseline all declared in this flake via native
> `services.k3s` options (the `k3s-nix` pattern), validated by a `nixosTest` in
> CI. One source, one `switch`, reconstructible from git, air-gap-capable. Only
> the experiments you throw at it stay runtime. No GitOps framework or manifest
> DSL is a *dependency* — they're escalation paths and themselves things to test.

---

## 1. Goal

Stand up a multi-node Kubernetes cluster on `kepler`, each node a NixOS MicroVM,
the whole thing declared in this dendritic flake. One `just switch-kepler` brings
the cluster into existence; wiping VM disks and re-deploying reconstructs it.

The cluster is a sandbox for testing tools (Helm charts, operators, CNI/CSI
experiments, GitOps controllers) against a realistic topology: a dedicated
3-node control plane and a scalable worker pool (3→5). DaemonSets, node affinity,
drains, rolling updates, control-plane-vs-worker scheduling all behave like a
real cluster, unlike a single-node or stacked setup.

### Responsibility boundary — *NixOS-native, top to bottom*

The design goal (per "propose a NixOS-native cluster") is that **everything up to
and including the cluster's platform baseline is Nix-defined** — only the
ad-hoc experiments you throw at it are runtime. The line moves *down* one layer
vs a typical "Nix owns the host, kubectl owns the cluster" split:

| Layer | Owner | Where it lives |
|---|---|---|
| Host OS, ZFS, GPU/AI-serving, NAS | **NixOS** (`kepler` host) | this flake (unchanged) |
| Hypervisor + VM definitions (vcpu/mem/net/disk) | **NixOS** (microvm.nix on `kepler`) | this flake |
| Guest OS of each node (NixOS) | **NixOS** (per-VM nixosConfiguration) | this flake |
| k3s server/agent, embedded etcd, hardening flags | **NixOS** (`services.k3s`) | this flake |
| **Platform baseline** — default-deny netpol, PSA config, metrics-server, ingress (CNI netpol is built into k3s) | **NixOS** (`services.k3s.manifests` / `autoDeployCharts` / `images`) | this flake (§5.9) |
| Pinned workload **images** (air-gap, reproducible) | **NixOS** (`services.k3s.images`) | this flake |
| *Experiment* workloads (the tools under test) | **kubectl / Helm / a GitOps controller you're testing** | *not* this flake (mutable cluster state) |

The k3s native options make the platform layer pure Nix: `manifests` renders Nix
attrsets → AddOn YAML the server auto-applies; `autoDeployCharts` runs Helm
charts (fetched at *build* time) via k3s's helm-controller; `images` bakes
container images into the node closure so the cluster needs nothing at runtime
(air-gap-capable). Only what you're actively *testing* stays runtime — same
spirit as "NixOS owns the host, not the app's data."

## 2. Current state (baseline)

| Part | Detail |
|---|---|
| Host | `kepler`, Ryzen 5 3600 (6c/12t), **128 GB RAM** (planned), RTX 3070 |
| Storage | fast-pool RAIDZ1 (~1.4 TB SSD), bulk-pool (planned HDD) — `hardware.nix` |
| Already running | rootless podman AI-serving (GPU via CDI), NFS+SMB NAS, syncthing, sanoid |
| Virt today | podman only; **no KVM/libvirt on kepler**. `kvm-amd` module is loaded (`hardware.nix:17`) ✓ |
| microvm.nix | present in `flake.lock` transitively (via hermes-flake), **0 references**, not a direct input |

## 3. Locked decisions (from scoping)

1. **Distro: k3s**, not vanilla `services.kubernetes`. Lighter, NixOS module is
   first-class (`clusterInit`/`serverAddr`/`manifests`/`autoDeployCharts`),
   built-in ServiceLB so `LoadBalancer` services get an IP with no cloud
   provider.
2. **VM stack: microvm.nix**, not libvirt. Declarative, NixOS-native, VMs are
   `nixosConfigurations` that reuse fleet modules — fits the dendritic flake.
   libvirt (used on discovery for an opaque HAOS appliance) is the wrong tool
   when the guest is itself NixOS.
3. **Topology: dedicated control plane + worker pool.** Three k3s **server**
   VMs (embedded etcd HA, tainted `NoSchedule` → control-plane only) + four
   k3s **agent** VMs (workloads land here). Mirrors a real cluster's CP/worker
   separation, not a stacked all-in-one.
   - Control plane count is **3, not 2**: etcd needs an odd majority. 2 servers
     halt the cluster if *either* dies (quorum 2-of-2) — strictly worse than 1.
     3 tolerates one failure.
   - Host is the real SPOF — irrelevant for a test env; the value is realistic
     multi-node + CP/worker behaviour.
4. **GPU stays on the host.** RTX 3070 remains bound to AI-serving (podman/CDI).
   Cluster is CPU-only. No VFIO passthrough, no IOMMU work, AI-serving untouched.
5. **Private node subnet, two endpoints published on the LAN via a kepler L4 LB.**
   Nodes live on a host-private subnet on kepler (`10.250.0.0/24`), invisible to
   the LAN. kepler runs a NixOS `services.nginx` stream LB publishing two fixed
   LAN IPs: **admin `192.168.10.245`** (→ the 3 CP apiservers) and **ingress
   `192.168.10.250`** (→ worker ingress NodePort). No in-cluster kube-vip/MetalLB
   (§10b). SWAG on `discovery` layers domain + TLS on top. No WAN exposure. (§5.3.)
6. **NixOS-native platform layer, no framework dependency** (from the framework
   study, §5.9). The cluster's *baseline* (CNI policy, default-deny netpol, PSA
   config, metrics-server, ingress) is declared in this flake via the native
   `services.k3s.manifests` / `autoDeployCharts` / `images` options — the same
   pattern `k3s-nix` (rorosen) uses. **No** GitOps framework (nixidy/ArgoCD) or
   manifest DSL (kubenix) is a *dependency*; they are escalation paths and
   themselves things to test (§5.9). Reproducible, air-gap-capable, one source.
7. **CI = NixOS VM test.** The whole cluster is exercised by a `nixosTest`
   (`pkgs.testers.runNixOSTest`) that boots the nodes in a VM, waits for
   `kubectl get nodes` Ready and the platform AddOns deployed — run in the
   existing CI matrix *before* anything touches kepler. This is the native win a
   hand-rolled or imperative cluster can't get for free (§5.10).

## 4. The constraints that shape it

- **CPU overcommit is fine, RAM is not the bottleneck.** Start at 6 VMs (3 CP +
  3 workers); the **5-worker target is 8 VMs** → vCPU overcommit 3×1 + 5×4 = 23
  on 12 threads (~1.9×) is acceptable for a test cluster; KVM time-slices. 128 GB
  means RAM stays comfortable even at the target (3×2 + 5×16 = 86 GB, leaves
  ~42 GB for host + AI-serving + ZFS ARC). Worker count is scalable (§5.6); the
  **ceiling is RAM** — well above the planned 5.
- **VM disks on ZFS.** fast-pool zvols give the VMs snapshot/rollback + ARC
  caching for free. The `/nix/store` is shared read-only from the host via
  virtiofs so three NixOS guests don't triplicate the store.
- **etcd hates slow disks.** Embedded etcd wants low fsync latency; the SSD
  RAIDZ1 is adequate. Keep VM root/data volumes on fast-pool, never bulk-pool.
- **Boot/lifecycle.** microvm runs each VM as a `microvm@<name>` systemd service
  on the host; `microvm.autostart` brings them up at boot. A config change to a
  guest needs the VM rebuilt + restarted (declarative redeploy, not live edit).

## 5. Architecture

### 5.1 Promote microvm.nix to a direct input
`flake.nix`: add
```nix
microvm = {
  url = "github:microvm-nix/microvm.nix";
  inputs.nixpkgs.follows = "nixpkgs";
};
```
(Today it only exists transitively under hermes-flake — not usable directly.)

### 5.2 New host aspect — `flake.modules.nixos.kepler-k3s-cluster`
Imported by `modules/hosts/kepler/default.nix`. Pulls in the microvm host module
and declares the seven node VMs (3 control-plane + 4 worker), ideally generated
from a small topology table rather than copy-paste (fleet convention — see
`syncthing-fleet`). Sketch:
```nix
imports = [ inputs.microvm.nixosModules.host ];
# nodes = { cp-1 = {role="init";}; cp-2 = {role="server";}; cp-3 = {role="server";};
#           w-1..w-4 = {role="agent";}; }  -> generate microvm.vms.<name> + autostart
microvm.autostart = [ "cp-1" "cp-2" "cp-3" "w-1" "w-2" "w-3" ]; # workers from workerCount
microvm.vms.cp-1 = { config = import ./node.nix { role = "init";   profile = "cp"; ... }; };
microvm.vms.w-1  = { config = import ./node.nix { role = "agent";  profile = "worker"; ... }; };
# ...
```
Each guest config = `profile-base` (trimmed) + a shared `k3s-node` module
parameterised by `role` (init/server/agent) and `profile` (cp/worker).

### 5.3 Networking — **decided: private node subnet, two endpoints published on the LAN**
**Hybrid.** Nodes live on a **host-private subnet** (`10.250.0.0/24`,
systemd-networkd bridge on kepler, kepler = gateway) — node/pod/etcd/flannel
traffic is isolated, VMs invisible to the LAN. But the cluster's **two service
endpoints are published on the LAN** at fixed addresses:

| Endpoint | LAN IP | What | Backing (private side) |
|---|---|---|---|
| **admin** | **192.168.10.245** | kube-apiserver (kubectl) | the 3 CP apiservers `10.250.0.{11,12,13}:6443` |
| **ingress** | **192.168.10.250** | ingress controller (DaemonSet) | worker NodePort `10.250.0.2x:30443` |

**How the LAN IPs reach the private cluster — kepler is an L4 load-balancer**
(revised in grilling round 2, §10b: drops kube-vip *and* MetalLB). kepler already
owns the private bridge (gateway `10.250.0.1`) and the LAN NIC, so it runs a plain
NixOS **`services.nginx` stream** (or haproxy) that load-balances both endpoints —
the k3s-documented "external LB / fixed registration address" HA pattern:
- `192.168.10.245:6443` **and** `10.250.0.1:6443` → upstream {cp-1,cp-2,cp-3}:6443
  (health-checked; LAN side = external admin, private side = node registration).
- `192.168.10.250:443` → upstream {workers}:30443 (ingress controller NodePort).

This keeps VMs **single-homed** (private only), needs **no in-cluster LB
controller** (no kube-vip DaemonSet, no MetalLB L2 segment, no ServiceLB
arbitrary-IP problem — see §10b/N2), and puts HA fronting where it naturally
belongs: on the one host that's mandatory anyway. (In-cluster kube-vip/MetalLB
remain available later *as things to test*, not as the baseline.)

**SWAG adds domain + TLS on top (not the only path now).** Since `.245`/`.250` are
LAN-reachable, you *can* hit them directly (`kubectl` → `https://192.168.10.245:6443`,
ingress → `http://192.168.10.250`). The existing **SWAG** on `discovery`
(`servarr/machines/discovery/networking.yml`, already proxies kepler/orion) layers
nice names + certs:
- `k8s.<HOMELAB_DOMAIN>` → admin, **stream / TLS-passthrough** (apiserver does its
  own mTLS — SWAG must not terminate), upstream `192.168.10.245:6443`.
- `*.k8s.<HOMELAB_DOMAIN>` → ingress wildcard, normal SWAG TLS + fail2ban,
  upstream `192.168.10.250:443`.

**Resolves:**
- *kubectl access*: kubeconfig server `https://k8s.<HOMELAB_DOMAIN>` (or the raw
  `.245`); apiserver `--tls-san=192.168.10.245,k8s.<HOMELAB_DOMAIN>,10.250.0.1`.
- *agent→CP target*: agents/joining-servers use the kepler LB's **private** side
  `serverAddr=https://10.250.0.1:6443` → fronts all 3 CPs → no single-CP SPOF for
  registration. The LAN `.245` is the same LB for *external* admin.
- *ingress reachability*: stable LAN IP `.250` + SWAG wildcard.

**Cross-repo:** the SWAG proxy-confs are a **`servarr` leaf change**
(`machines/discovery/`), landed leaf-first per the coupling map, then kepler
deploy. `TODO(erik)`: confirm SWAG's nginx `stream{}` module is enabled for the
apiserver TLS-passthrough (off by default in SWAG); reserve `.245`/`.250` in the
router so DHCP never hands them out.

### 5.4 Per-VM resources (starting point, tune later)
| role | count | vCPU | RAM | root vol | data vol |
|---|---|---|---|---|---|
| control-plane (`cp-1..3`) | 3 | 1 | 2 GB | 16 GB image | 8 GB etcd image |
| worker (`w-1..N`) | **3 → 5** | 4 | 16 GB | 20 GB image | 40 GB image |

**Storage correction:** microvm `volumes` are **image files microvm auto-creates**;
it does *not* manage zvols (block-device passthrough via `image=/dev/zvol/…`
exists but is an [unclean path, astro/microvm.nix#273](https://github.com/astro/microvm.nix/issues/273)
and the zvol must pre-exist). So volumes live as files under a dedicated ZFS
dataset (`fast-pool/microvms`, `recordsize=64k`, own sanoid policy) — we still
get ZFS snapshots + compression + ARC at the *dataset* level, with zero
per-VM zvol bookkeeping. Simpler and supported.

`1 vCPU / 2 GB` per CP is the documented k3s server floor (≤10 nodes, idle) —
adequate for a sandbox, not for heavy apiserver load. etcd on its own small zvol
per CP node (low fsync latency matters). **Start at 3 workers** (`workerCount =
3`): 3×1 + 3×4 = 15 vCPU / 3×2 + 3×16 = 54 GB / 6 VMs. **Scale target 5
workers**: 23 vCPU / 86 GB / 8 VMs — still comfortable on 128 GB. Worker count is
a knob, not a constant — see §5.6.

`microvm.hypervisor = "cloud-hypervisor"` (fast boot, KVM, virtiofs supported) —
`TODO(erik)`: qemu if a cloud-hypervisor limitation bites. `/nix/store` shared
read-only via virtiofs; `/var/lib/rancher` on a dedicated zvol so cluster state
survives a guest rebuild and lands in sanoid snapshots.

### 5.5 k3s wiring (`modules/hosts/kepler/k3s/node.nix`)
- **cp-1:** `role = "server"; clusterInit = true;` — bootstraps embedded etcd.
- **cp-2/3:** `role = "server"; serverAddr = "https://10.250.0.1:6443";` — join
  etcd via the **kepler LB** (§5.3), which fronts all 3 CPs, not a single one.
- **Control-plane nodes tainted** `node-role.kubernetes.io/control-plane:NoSchedule`
  (k3s flag `--node-taint`) so workloads only land on workers.
- **w-1..N:** `role = "agent"; serverAddr = "https://10.250.0.1:6443";`
  `agentTokenFile`. **Decided** (§5.3/§10b): all joins target the kepler L4 LB →
  CP failover for registration, no single-CP SPOF, and no in-cluster kube-vip.
- **Only one secret exists: the k3s join token.** It need only live on the
  **host** (kepler already runs sops-nix); guests receive it via a
  `microvm.shares` read-only mount (or `microvm.credentialFiles`) and point
  `tokenFile`/`agentTokenFile` at it. **Guests run no sops and hold no age key**
  — this sidesteps the persistent-guest-key problem entirely (see G3). Use
  `tokenFile`, never the plain `token`/`agentToken` (those land it
  world-readable in `/nix/store`). Host-side sops is *optional polish* here — it
  lets the token live in the repo reproducibly; the threat model (LAN-isolated,
  disposable cluster) doesn't demand it.
- `services.k3s.disable = [ "traefik" ]` — bring an ingress under test instead;
  **keep ServiceLB**. `TODO(erik)`: confirm.
- Declarative addons via `services.k3s.manifests` / `autoDeployCharts` if we want
  a baseline (e.g. metrics-server, a CNI) baked in vs applied by hand. For a
  *testing* cluster, lean minimal — bake almost nothing, apply tools by hand.
- Firewall between nodes: 6443 (api), 2379-2380 (etcd), 10250 (kubelet),
  8472/udp (flannel vxlan), plus ServiceLB ranges. Open within the cluster
  subnet only.

### 5.6 Scalable worker pool (the "add a node = change a number" knob)
Workers are **generated**, not hand-listed — same idiom as `syncthing-fleet`
(one table → many definitions). A single option drives the count:
```nix
options.kepler.k3s.workerCount = lib.mkOption { type = lib.types.int; default = 3; }; # start 3, scale to 5
# also: workerVcpu / workerMem options so size is tunable, not just count.

config.microvm.vms = let
  workers = lib.genAttrs
    (map (n: "w-${toString n}") (lib.range 1 cfg.workerCount))
    (name: let i = lib.toInt (lib.removePrefix "w-" name); in {
      config = import ./node.nix {
        role = "agent";
        profile = "worker";
        index = i;
        ip  = "10.250.0.${toString (20 + i)}";          # deterministic from index
        mac = "02:00:00:00:00:${lib.fixedWidthString 2 "0" (lib.toHexString i)}";
      };
    });
in workers // { cp-1 = {...}; cp-2 = {...}; cp-3 = {...}; };

config.microvm.autostart =
  [ "cp-1" "cp-2" "cp-3" ] ++ map (n: "w-${toString n}") (lib.range 1 cfg.workerCount);
```
Everything per-worker derives from the index — IP, MAC, volume image path
(`fast-pool/microvms/w-${i}.img`), VM name. **Scale up:** bump `workerCount`,
`just switch-kepler`; microvm starts the new VM, k3s agent auto-joins with the
shared token. No new manifests, no per-node files.

**Scale-down is not symmetric** — a removed agent leaves a stale `NotReady`
node object. Procedure: `kubectl drain w-N --ignore-daemonsets --delete-emptydir-data`
→ `kubectl delete node w-N` → lower `workerCount` → switch (microvm stops the
VM) → delete its image file. `TODO(erik)`: fold this into a `just scale-down N`
helper so it's one command, not four. `genList` makes shrinking only ever drop
the *highest-numbered* workers (stable identities) — don't reorder.

Control plane stays fixed at 3 (etcd quorum); only the worker pool scales.

### 5.7 Deploy / lifecycle
- Built + switched via existing **`just switch-kepler`** — no new remote path;
  the VMs are part of kepler's toplevel. (microvm guests are built as part of the
  host closure.)
- New `just` recipes likely wanted: `cluster-status` (kubectl/etcd health),
  `cluster-reset` (stop VMs, delete data images, re-init). `TODO(erik)`.
- `modules.upgradeHealthCheck.criticalUnits` on kepler: consider adding the
  `microvm@cp-*.service` / `microvm@w-*.service` units so a broken VM blocks
  unattended upgrade.
  `TODO(erik)` — or deliberately exclude (test cluster shouldn't gate host
  upgrades). Probably **exclude**.

### 5.8 Hardening (defense-in-depth, layered)
Two layers harden independently: the **VM boundary** (already a win over running
k3s on the host) and the **cluster config**. k3s passes many CIS controls
out-of-the-box (`PodSecurity` + `NodeRestriction` admission on by default); the
rest is opt-in. Because this is a *test* cluster, hardening that breaks the
"throw a chart at it and see" loop is a judgment call — `enforce: restricted`
PSA in particular will reject sloppy test manifests. Mark which to bake now vs
later as `TODO(erik)`.

**Host / VM layer (the isolation dividend):**
- Cluster runs in MicroVMs, **not on kepler directly** — a container escape lands
  in a 16 GB throwaway VM, not on the NAS/GPU host. This is the headline harden.
- GPU/AI-serving stay on the host, never exposed to the cluster (decision §3.4).
- Cluster on a **host-private subnet** (§5.3 option B) → not reachable off-LAN;
  no WAN/Tailscale exposure of the apiserver or services. Firewall on the host
  gates the only ingress.
- Guests are minimal NixOS (`profile-base` trimmed) — small attack surface, no
  desktop/peripheral cruft.

**k3s / cluster layer — per the k3s CIS hardening guide.** Set on the **server**
nodes (maps to `services.k3s.extraFlags` / a generated `configPath`):
- `protect-kernel-defaults = true` + the kubelet sysctls
  (`vm.panic_on_oom=0`, `vm.overcommit_memory=1`, `kernel.panic=10`,
  `kernel.panic_on_oops=1`) via `boot.kernel.sysctl` in the **guest** config —
  k3s refuses to start with `protect-kernel-defaults` unless these are set.
- `secrets-encryption = true` → API server encrypts Secrets at rest in etcd
  (AES-CBC). On by a flag; can't be toggled live without a server restart.
- **PodSecurity admission** via `admission-control-config-file=…/psa.yaml`.
  **Decided: cluster default `enforce: baseline`**, `kube-system` exempt; opt a
  dedicated namespace up to `restricted` (label `pod-security.kubernetes.io/enforce=restricted`)
  when *testing* hardening. Baseline blocks the genuinely dangerous (privileged,
  host namespaces/ports, hostPath) cluster-wide without rejecting every ordinary
  test chart. Tighten the default to `restricted` later if modelling production.
- `kube-apiserver-arg`: `enable-admission-plugins=NodeRestriction,EventRateLimit`,
  audit logging (`audit-log-path`, `audit-policy-file`, maxage/backup/size),
  `service-account-extend-token-expiration=false`.
- `kubelet-arg`: `streaming-connection-idle-timeout=5m`, the CIS
  `tls-cipher-suites` allowlist.
- `kube-controller-manager-arg`: `terminated-pod-gc-threshold=100`.
- The `psa.yaml` / `audit.yaml` are **Nix-generated files** placed read-only in
  the guest store and pointed at via the args — fits NixOS perfectly (no mutable
  hand-edited config).

**Cluster-runtime layer (applied as manifests, not host config):**
- **Default-deny NetworkPolicy** per namespace, then allow only needed flows.
  **Correction (was wrong in an earlier draft):** stock k3s *already enforces*
  NetworkPolicy via an embedded kube-router netpol controller on top of flannel —
  no CNI swap needed for basic default-deny. Cilium/Calico is only for *advanced*
  features (L7, eBPF observability) and is a `--disable-network-policy` +
  alternate-CNI choice, which is itself a worthwhile thing to test — not a
  prerequisite for hardening.
- **RBAC least-privilege**: namespaced `Role`/`RoleBinding` over Cluster*; no
  workload gets `cluster-admin`; `automountServiceAccountToken: false` by default.
- These are workload-layer (the §1 boundary) — seed a baseline set via
  `services.k3s.manifests` if we want them present at bootstrap, else apply by
  hand. For a test cluster, baking **default-deny + PSA** is the high-value
  minimum; leave the rest to per-experiment policy.

Note the tension (resolved §5.8): full CIS `restricted` PSA makes a *testing*
cluster annoying. **Decided: bake host/VM layer + secrets-encryption + audit +
`baseline` PSA + a default-deny netpol now**; `restricted` stays a per-namespace
opt-in for when you test hardening itself.

### 5.9 Framework study → the NixOS-native workload layer
Studied the four Nix-on-k8s frameworks to decide what (if anything) to adopt.
Each operates on a **different layer** — the key realisation is they are not
alternatives to each other, they stack:

| Tool | Layer it owns | Mechanism | Verdict here |
|---|---|---|---|
| **`services.k3s.{manifests,autoDeployCharts,images}`** (native nixpkgs) | platform AddOns *inside* the cluster | `manifests` = Nix attrset → AddOn YAML auto-applied by the server; `autoDeployCharts` = Helm via k3s helm-controller (chart fetched at build); `images` = images baked into node closure | **Adopt — this is the foundation.** Zero new inputs, pure NixOS, air-gap-capable. |
| **`k3s-nix`** (rorosen) | the *whole* cluster (infra + deploys) as pure Nix + **NixOS VM tests** | server.nix/agent.nix configs, sops-nix secrets, `nixosTest` CI, qcow2 outputs | **Adopt as the reference pattern**, not as an input. It *is* the native blueprint — we re-implement its ideas in our dendritic flake + microvm. Drives §5.5/§5.10. |
| **kubenix** | manifest *authoring* | typed Nix module options for every k8s resource (`kubernetes.resources.<kind>.<name>…`), OpenAPI-generated, eval-checked → JSON manifests | **Optional, later.** If raw `services.k3s.manifests` attrsets get unwieldy/untyped, layer kubenix to generate them. Not needed to start. |
| **nixidy** | GitOps *delivery* | "cluster as NixOS" → renders plain YAML (rendered-manifests pattern) for **Argo CD** to sync; per-environment modules | **Escalation path / thing-to-test.** Adopt only when you want real pull-based GitOps — and that's itself a tool the sandbox exists to try. |
| kubix / kubernixos / Fractal | manifest generators | lighter / experimental (Fractal unmaintained) | Skip. |

**Decision (native, no framework dependency):**
- **Platform baseline lives in Nix via the native k3s options** — this *is* the
  NixOS-native cluster. The baked set (no kube-vip/MetalLB — kepler is the LB,
  §5.3/§10b):
  - **ingress controller** (ingress-nginx) as a **DaemonSet on workers with a
    fixed NodePort** (`30443`), the kepler-LB upstream for `.250`. Via
    `autoDeployCharts` (Helm) or manifests.
  - **default-deny NetworkPolicy** per namespace (enforced by k3s's built-in
    netpol controller — no CNI swap, §5.8).
  - **PSA config** (`psa.yaml`, default `baseline` — §5.8).
  - **metrics-server** (`autoDeployCharts`).
  - **`images`** pins + pre-loads every image above so the cluster — and the
    `nixosTest` (no internet, §5.10/G5) — pull nothing at runtime.
  - Control-plane HA fronting is **not** an in-cluster AddOn here — it's the
    kepler `services.nginx` stream LB (§5.3), a host-NixOS service.
- **`k3s-nix` is the blueprint** for the build wiring (server/agent split,
  token handling, the VM-test CI in §5.10). Read it; don't depend on it.
- **kubenix only if** untyped attrsets hurt — a refactor, not a prerequisite.
- **nixidy/ArgoCD, Flux = workloads under test**, never the foundation. The
  whole point of the sandbox is trying these; baking one in would defeat it.

Net: one flake, one `switch`, the platform reproducible and air-gap-capable; the
experiments stay runtime.

### 5.10 CI — boot the whole cluster in a NixOS VM test (the native win)
`k3s-nix`'s strongest idea: a `nixosTest` that builds and **boots the cluster in
QEMU**, then asserts health — caught in CI *before* a single byte hits kepler.
- `pkgs.testers.runNixOSTest { nodes = { cp1 = …; cp2 = …; w1 = …; }; testScript
  = … }` — reuse the *same* `services.k3s` node modules the real VMs use.
- `testScript`: `start_all()`, wait for k3s units, `cp1.wait_until_succeeds("k3s
  kubectl get nodes | grep -c Ready … == N")`, assert etcd quorum, assert the
  baked AddOns (`kubectl -n kube-system get deploy metrics-server`) reach Ready,
  assert a `restricted`-namespace pod is admitted and a privileged one rejected
  (proves PSA), assert default-deny blocks cross-namespace traffic.
- Wire into the repo's existing **CI matrix** (CLAUDE.md: "CI evaluates all five
  hosts") as an extra check. A scaled-down 1cp+1agent variant keeps CI fast;
  full topology on demand.
- This makes the cluster *testable as code* — the property that separates a
  NixOS-native cluster from a pile of YAML.

## 6. Open questions — `TODO(erik)` (judgment)

**Resolved:**
- ~~Networking shape~~ → **private nodes + 2 LAN-published endpoints**: admin
  `192.168.10.245`, ingress `192.168.10.250`, kepler DNAT, SWAG domain/TLS (§5.3).
- ~~Secret delivery~~ → host-only token, shared in read-only; no guest sops (§5.5/G3).
- ~~kubectl access~~ → `k8s.<HOMELAB_DOMAIN>` / raw `.245`; apiserver `--tls-san` (§5.3).
- ~~agent→CP target~~ → private kube-vip VIP `10.250.0.10` (§5.3/§5.5).
- ~~Platform baseline set~~ → kube-vip + ingress-nginx + default-deny + PSA +
  metrics-server, all baked w/ pinned images (§5.9).
- ~~PSA strictness~~ → default `baseline`, per-namespace `restricted` opt-in (§5.8).
- ~~CP sizing (G1)~~ → start 1 vCPU, tune post-deploy if etcd flaps (not gating).

**Still open:**
- **SWAG `stream{}` + IP reservations** (§5.3): confirm SWAG's nginx `stream`
  module is enabled for the apiserver TLS-passthrough (default off); reserve
  `192.168.10.245`/`.250` in the router so DHCP never collides.
- **LB stream timeouts** (§10b/N4): set generous `proxy_timeout` on the kepler
  stream LB + SWAG so long-lived `kubectl watch/exec/logs -f/port-forward` survive.
- **Distro spike?** (§12): accept `services.k3s`-native, or spike
  `services.kubernetes`+`easyCerts` to compare the "NixOS-owns-PKI" feel.
- **Whole-cluster bounce on nixpkgs bumps** (G2): exclude VM units from
  `upgradeHealthCheck` *and* decide stagger-restart vs accept-downtime.
- **CNI** (§5.8): stock flannel+netpol (default) vs Cilium/Calico — a
  *thing-to-test*, not a prerequisite.
- **kubenix?** (§5.9): typed authoring later vs raw attrsets — defer.
- **bulk-pool interaction**: none for now; VM storage is fast-pool only.
- **Repo split** (§11): confirm Option 0-now / Option 2-later; pre-name the
  future workloads leaf repo.
- **GitOps controller** (§5.9): nixidy+ArgoCD / Flux — defer; adopt as a
  *workload under test*, never the foundation.

## 7. Out of scope

GPU/CUDA workloads in-cluster (GPU stays on host), WAN/Tailscale exposure of
cluster services, production HA semantics (single physical host = SPOF by
design), persistent app data backup (test workloads are disposable).

## 8. Rollout

1. Promote microvm.nix to a direct input; `git add` new files (untracked files
   are invisible to flake eval). Read `k3s-nix` as the blueprint.
2. **`nixosTest` first (TDD).** Write the VM-test (§5.10) for a minimal
   1cp+1agent cluster and get it green — this validates the `services.k3s` node
   module in QEMU with zero kepler risk, and becomes the CI gate.
3. Build a **single** throwaway microvm on kepler (1 node, `clusterInit`) — prove
   the *real* stack: cloud-hypervisor + virtiofs `/nix` + tap networking +
   k3s-comes-up. (The test proves config; this proves the hypervisor plumbing.)
4. Generalise to the shared `k3s-node` module; add cp-2/3 (`serverAddr`, etcd
   join) then the 3 starting agents; verify `kubectl get nodes` shows 6 Ready (3
   control-plane tainted, 3 workers), etcd quorum healthy. Then bump
   `workerCount` to prove scale-up adds a node cleanly.
5. Wire the sops token, hardening flags (§5.8), firewall rules, chosen
   networking shape.
6. **Bake the platform baseline** via `services.k3s.{manifests,autoDeployCharts,
   images}` (§5.9) — default-deny netpol + PSA + metrics-server + ingress;
   extend the `nixosTest` to assert each reaches Ready.
7. `just` helpers (status/reset/scale-down); document in `docs/`.
8. Verify per §below, then leave it running as the sandbox.

## 9. Verify

- `just dry kepler` clean before switch; skim diff for surprises.
- After `just switch-kepler`: `systemctl status 'microvm@*'` all 6 active (at
  the starting count); from a CP node, `k3s kubectl get nodes` → 6 `Ready` (3
  control-plane tainted, 3 workers), `kubectl get --raw /healthz`, etcd member
  list shows 3 healthy; a test pod schedules onto a worker, never a CP node.
- Host AI-serving untouched: GPU containers still up (`podman ps`), `nvtop`
  shows the models loaded — proves the cluster didn't disturb GPU/CDI.
- A green rebuild is not proof the cluster formed — check node/etcd state.

## 10. Adversarial review (grilling) — risks the happy path hides

Self-critique pass. Severity: 🔴 could sink the design / 🟡 needs a decision /
🟢 noted. Two factual errors already corrected inline (k3s netpol is built-in
§5.8; microvm uses image files not zvols §5.4).

| # | Sev | Risk | Mitigation / decision |
|---|---|---|---|
| G1 | 🟢 | **etcd on RAIDZ1 + overcommitted 1-vCPU CP nodes** → fsync-heavy etcd on a parity pool (poor sync IOPS) under CPU steal can flap: heartbeat timeouts → leader elections → instability. The "mini CP" decision fights etcd's needs. | **Not gating — tunable post-deploy.** vCPU/RAM are just numbers in the VM def; start at 1 vCPU, and if `etcd` logs heartbeat/election warnings, bump to 2 vCPU + pin (`cpuset`), tune the etcd dataset (`logbias=latency`), re-switch. Watch, don't pre-solve. |
| G2 | 🔴 | **Whole-cluster simultaneous bounce on nixpkgs bumps.** A `nixpkgs` update changes every guest closure → all 6 microvms rebuild + restart together on `switch` → etcd quorum lost cluster-wide, not a rolling update. Fleet autoUpgrade makes this unattended. | **Exclude microvm units from `upgradeHealthCheck`** (already leaning) *and* don't auto-bounce: stagger restarts (serialize `microvm@*` via `After=`/timer) or accept manual cluster upgrades. For a sandbox, downtime is fine — but **document it's not rolling**. |
| G3 | 🟢 | **Guests don't need sops at all** (resolved). The only secret is the k3s join token; the original "per-VM sops" lean forced a persistent guest age key (stable SSH host key on ephemeral roots — chicken-egg). | **Delete guest-sops.** Token lives host-only (kepler's existing sops, or even a generated file — it's a disposable LAN cluster); shared into guests read-only via `microvm.shares`, `tokenFile` points at it. Guests run no sops, hold no key. See §5.5. |
| G4 | 🟢 | **Private subnet makes cluster IPs unreachable from the LAN** — original concern. | **Resolved (§5.3):** two endpoints published as fixed LAN IPs (`.245`/`.250`) via kepler's L4 LB; SWAG adds domain/TLS. No per-service forwards. |
| G5 | 🟡 | **`nixosTest` can't reach the internet** (sandboxed) → any AddOn that pulls images at runtime fails the test. Validating the platform baseline *requires* every image baked via `services.k3s.images`. | Make `services.k3s.images` mandatory for anything in the baked baseline; the test is what *forces* this discipline (a feature). But note **store/closure bloat** — CNI+metrics+ingress images = GB in `/nix`. |
| G6 | 🟡 | **6-node HA cluster in CI is heavy** — `runNixOSTest` boots all nodes in QEMU on the runner; 3-server etcd + agents may OOM/timeout. | CI runs a **scaled-down 1cp+1agent** variant (already noted); full topology only on-demand/locally. Accept CI proves *config*, not *HA behaviour*. |
| G7 | 🟢 | **PSA `restricted` vs ServiceLB/system pods** — svclb pods use hostPorts/privileged; they live in `kube-system` (exempted) so OK, but any baked AddOn in a `restricted` namespace must ship a compliant securityContext. | Keep `kube-system` exempt; author baked manifests to pass `restricted`; start namespaces at `baseline` (§5.8). |
| G8 | 🟢 | **clusterInit start race** — cp-2/3 boot before cp-1 finishes etcd init. | k3s agents/servers retry `serverAddr` until reachable; converges. Optionally order `microvm@cp-1` first. No action needed. |
| G9 | 🟢 | **microvm + ZFS + virtiofs `/nix`** — guest closure must be in the *host* store to share; works, but kepler's store grows by the union of all guest closures (largely shared). | Expected; `nix-collect-garbage` covers it. Monitor fast-pool/M.2 free space. |

### 10b. Grilling round 2 — the LB/DNAT design (after the `.245`/`.250` decision)

| # | Sev | Risk | Mitigation / decision |
|---|---|---|---|
| N1 | 🟡→✅ | **kube-vip *inside* the cluster + kepler DNAT on top is two LB layers for one job.** kepler must already own/forward `.245`/`.250`; adding an in-cluster kube-vip DaemonSet (+ its image, + a manifest) duplicates what kepler is already positioned to do. | **Adopt the simpler, more host-native pattern: kepler *is* the L4 LB.** A plain NixOS `services.nginx` (stream) / haproxy on kepler load-balances apiserver → the 3 CPs and ingress → worker NodePorts. This is the k3s-documented "external LB / fixed registration address" HA approach. **Drops kube-vip *and* MetalLB.** §5.3 revised. |
| N2 | 🔴→✅ | **ServiceLB can't hand out an arbitrary `10.250.0.200`** — k3s ServiceLB (klipper-lb) binds *node* IPs via hostPorts; a dedicated LB IP needs MetalLB (which then wants its own L2 segment + `--disable servicelb`). The earlier "ServiceLB IP 10.250.0.200" was wrong. | Same fix as N1: **no in-cluster LB controller at all.** Ingress runs as a DaemonSet with a NodePort; kepler's LB streams `.250:443` → `workers:nodePort`. No MetalLB, no ServiceLB-IP confusion. |
| N3 | 🟢 | **kepler is the SPOF for `.245`/`.250`** (and all VMs). HA control plane is learning-only, not real availability. | Accepted/by-design (single host). The LB-on-kepler doesn't add a SPOF — kepler is already one. Documented. |
| N4 | 🟡 | **Long-lived kubectl streams** (`watch`, `exec`, `logs -f`, `port-forward`) cross SWAG-stream → kepler-LB → CP. Default nginx/haproxy stream idle timeouts will sever them. | Set generous `proxy_timeout` on the kepler stream LB and SWAG `stream{}`; align with k3s `--kubelet-arg=streaming-connection-idle-timeout`. Note in module. |
| N5 | 🟢 | **Hairpin** — pods/host reaching the ingress via `.250` (its own LAN IP) need NAT hairpin/reflection. | Common; kepler nft `hairpin`/`masquerade` on the LB path, or use in-cluster DNS for east-west. Minor. |
| N6 | 🟢 | **secrets-encryption rotation in HA etcd** — `k3s secrets-encrypt` rotate commands are per-node and fiddly across 3 servers. | Enable at bootstrap (consistent), avoid live rotation on the sandbox. Ops note only. |

Net after both rounds: round 2 **simplified the design** — kepler-as-L4-LB
removes kube-vip + MetalLB (two components + two images + a manifest gone), is
more host-native, and fixes the ServiceLB-IP error (N2, was 🔴). Remaining real
opens: G2 (upgrade bounce) and N4 (stream timeouts). The design is now *simpler*
than when grilling started.

## 11. Should the cluster live in a second repo?

The fleet already uses the sister-repo pattern (servarr, hermes-flake,
home-assistant-config, klipper-biqu) with a clear rule (CLAUDE.md coupling map):
**this flake owns host OS; leaf repos own app/runtime config.** Three ways to
apply it here:

| Option | What moves out | Mirrors | Pro | Con |
|---|---|---|---|---|
| **0. Single repo** (status quo) | nothing — infra + platform baseline in `desktop-nixos` | — | one source, one `switch`, dendritic-native, nothing to bump | infra + experiments share a repo; cluster not independently versioned |
| **1. Infra as a flake module repo** | the `k3s-cluster` NixOS module + its `nixosTest`, exported as `nixosModules.k3s-cluster` | **hermes-flake** (exports module, consumed by kepler) | cluster independently CI'd/versioned/reusable; kepler just imports + passes host specifics (NIC, dataset) | cross-repo version-bump ceremony (the hermes `update-check`→`lock` dance) for a *sandbox*; splits kepler's config across repos — fights dendritic locality |
| **2. Workloads as a leaf repo** | only the *experiment/GitOps* manifests (nixidy env or plain YAML), delivered by an in-cluster controller | **servarr / home-assistant-config** (app config, host pulls) | clean GitOps story; matches the §1 boundary exactly (platform=flake, experiments=leaf); ArgoCD/nixidy land here naturally | needs a GitOps controller running (itself a thing-to-test); two repos to touch for a workload change |

**Recommendation:**
- **Infra + platform baseline stay in `desktop-nixos` (Option 0).** The microvm
  host config *is* kepler's config — splitting it out (Option 1) fights the
  dendritic model and adds the hermes-style bump dance for no early payoff. The
  hermes precedent works because hermes is a genuinely independent *package*;
  this cluster is host-coupled infrastructure.
- **When the workload layer outgrows hand-applied experiments, split *that* into
  a sister repo (Option 2)** — `kepler-cluster` (or similar) holding the GitOps
  content, pulled by an in-cluster ArgoCD/Flux you stood up *as a test*. This is
  the exact moment GitOps stops being a toy and the coupling-map rule says it
  belongs in a leaf repo. It also keeps `desktop-nixos` from accreting hundreds
  of app manifests.
- **Don't do Option 1.** Reusability/independent-versioning of the *infra* isn't
  worth the cross-repo friction for a single-host sandbox. Revisit only if a
  second physical host ever needs the same cluster module.

So: **one repo now; a workloads leaf repo later, exactly when you adopt GitOps.**
That keeps the NixOS-native infra thesis (§5.9) intact and reserves the
second repo for the layer that genuinely wants to live outside the OS flake.
`TODO(erik)`: confirm Option 0-now / Option 2-later, and pre-name the future
workloads repo so the coupling map can reference it.

## 12. Is there a *more* NixOS-native way to do the cluster?

Asked directly: yes — several, on two different axes. None beats the chosen
design for *this* goal, but the survey is worth recording so the choice is
informed, not default.

**Axis A — the k8s distro module (how the cluster itself is declared in Nix):**

| Approach | Nativeness | What it gives | Verdict |
|---|---|---|---|
| **`services.k3s`** (chosen) | native nixpkgs module | role/clusterInit/serverAddr/manifests/autoDeployCharts/images; built-in netpol + ServiceLB | **Keep.** Lightest, most ergonomic, air-gap-friendly. The pragmatic native choice. |
| **`services.kubernetes`** (vanilla) | **most native** — NixOS owns even the PKI | `roles = ["master" "node"]`, `easyCerts = true` → NixOS bootstraps a cfssl CA + all certs; flannel; addonManager | **More native, not better here.** NixOS-owned PKI is elegant but heavier, fiddlier (easyCerts is famously finicky), no ServiceLB, more components to keep Ready. Right answer only if "NixOS owns the certs too" is a hard requirement. |
| **`nixos-rke2`** (numtide) | native module, third-party | RKE2 (Rancher's CIS-hardened k8s) as a NixOS service — hardened-by-default | **Note as alternative.** If the goal were *production hardening* over *sandbox ergonomics*, this is the strongest native option. Overkill for a test cluster. |
| **`k3s-nix`** (rorosen) | pattern, not a module | the whole-cluster-in-Nix + `nixosTest` blueprint we already adopt (§5.9/§5.10) | **Already the blueprint.** |

**Axis B — the fleet/machine framework (how the *nodes* are managed):**

| Approach | What it is | Verdict |
|---|---|---|
| **microvm.nix + dendritic flake** (chosen) | VMs as NixOS configs in this flake | **Keep** — fits the existing repo model. |
| **clan.lol** (`clan-core`) | a genuinely NixOS-native *fleet* framework — declarative multi-machine inventory, cross-machine services, built-in overlay networking (WireGuard/zerotier), secrets (vars/sops), disko + nixos-anywhere provisioning, all from one flake | **The most "native way to do clusters" of *machines*** — but it manages NixOS hosts, **not Kubernetes**. It could *host* the microvms/k3s, but adds a whole framework + its mental model for a single-host sandbox. **Overkill now; the thing to evaluate if the fleet itself grows** (it would also touch pathfinder/orion/discovery, not just kepler — a fleet-wide decision, out of scope here). |
| **colmena / deploy-rs** | deployment drivers | orthogonal — we deploy via `just`/`nixos-rebuild`; no need. |

**Honest verdict:** the *most* native cluster would be `services.kubernetes`
(`roles` + `easyCerts`, NixOS-owned PKI) managed under **clan**. But "most native"
≠ "best for a disposable single-host test sandbox": that stack is heavier,
rougher, and clan is a fleet-wide commitment. **`services.k3s` on microvm.nix in
this flake is already squarely NixOS-native** — declared in Nix, reconstructible
from git, tested in a `nixosTest` — while staying light and ergonomic. Recorded
as a deliberate choice, with `services.kubernetes`/`nixos-rke2`/clan as the
escalation options if requirements change. `TODO(erik)`: accept k3s-native, or
want a spike of `services.kubernetes` + `easyCerts` to feel the difference?

## 13. Post-v1 improvements (2026-06-20)

Four refinements after the `v1` tag, batched together. **A and C touch the
guests** → land on a supervised `just switch-kepler` window (recreates the CP
microvms; D's stagger lengthens cold boot, see below).

### B — `meta.domain` (DRY the domain)

`pastelariadev.com` was hardcoded in five modules. Hoisted into a `readOnly`
`meta.nix` option (`config.domain`); hermes (agent + litellm URLs), the klipper
moonraker HA-power plugin, and this cluster's apiserver TLS SAN now reference it.
No behaviour change — pure de-duplication.

### C — etcd snapshots → kepler's bulk-pool

k3s embedded-etcd takes automatic snapshots (default every 12h, retain 5) but
wrote them to each guest's **ephemeral `root.img`** — lost if the volume is
recreated. Each CP guest now mounts a **per-CP virtiofs share** at
`/etcd-snapshots` backed by `/bulk/k3s-etcd-snapshots/<cp>` (bulk-pool ZFS, 15T),
and passes `--etcd-snapshot-dir=/etcd-snapshots`. Per-CP subdirs avoid any
cross-guest virtiofs write contention; restore is the standard
`k3s server --cluster-reset --cluster-reset-restore-path=<snapshot>` off `/bulk`.

### D — staggered cold boot

The `microvm@` units are `Type=notify`; on a cold/contended boot all 5 guests
raced their vsock ready-notify, occasionally tripping the (now 300s) start
timeout. Per-instance `After=` drop-ins (`overrideStrategy = "asDropin"` on the
template) order boot **cp-1 → cp-2 → cp-3**, workers after cp-1. `After=` is
ordering-only (no failure cascade). Trade-off: serial CP boot makes a full cold
start slower (~one CP-ready interval each) in exchange for no contention spikes.

### A — fleet observability of the cluster

Surveyed `dataplatform-gitops` (in-cluster kube-prometheus-stack + Alloy). For a
5-node sandbox that already has an **external** Grafana/Loki/Prometheus on
discovery, the reusable piece is their **Alloy log pipeline**, not the in-cluster
operator stack. Adopted **push-only, one agent**:

- **Logs (shipped):** a Grafana **Alloy DaemonSet** (`monitoring` ns) tails pod
  logs **via the k8s API** (`loki.source.kubernetes` — no hostPath, so it passes
  the PodSecurity **baseline**), keeps only its own node's pods (`NODE_NAME`
  downward-API filter), labels `cluster="pastelariadev"`, and pushes to
  discovery's Loki (`100.76.140.121:3100`). Chart fetched from the GitHub release
  tarball (grafana's helm repo doesn't serve tgz at the repo root).
- **Egress path:** cluster pods are NAT'd to kepler's LAN only, but discovery is
  **tailnet-only**. Added a masquerade of `10.250.0.0/24 → tailscale0` on kepler
  (`networking.nat.extraCommands`) so pod egress is SNAT'd to kepler's Tailscale
  IP — push-only, **no subnet-route advertisement** (nothing reaches into pods,
  no Tailscale-admin route approval needed).
- **Bonus fix:** discovery's *own* fleet Alloy module was remote-writing host
  metrics to `:9009` (Mimir, never deployed) — silently dropped. Repointed to
  Prometheus `:9090/api/v1/write` (receiver already enabled). Fleet-wide.

**Deferred (follow-up):** cluster **metrics** — node-exporter / cAdvisor+kubelet
scrape + **kube-state-metrics** → Prometheus `remote_write`. Each in-cluster
metrics source has a fiddly bit (kubelet bearer-token TLS, node-exporter host
mounts vs. PSA, KSM as a standalone Deployment) that's only verifiable live, so
it's split out from the reliable log path. k3s control-plane component
ServiceMonitors (`kubeScheduler`/`kubeControllerManager`/`kubeEtcd`/`kubeProxy`)
mostly don't scrape on k3s' single-binary server — skip them.

### Verify (on the supervised deploy)

1. `just dry kepler` clean (done — evaluates with the Alloy chart + egress rule).
2. `just switch-kepler`; confirm 5/5 nodes Ready and the staggered boot order in
   `journalctl -u microvm@cp-2 -u microvm@cp-3` (start After cp-1/cp-2).
3. `kubectl -n monitoring get ds alloy` → desired == ready (one per node);
   `kubectl -n monitoring logs ds/alloy` shows no Loki push 4xx/5xx and no RBAC
   `forbidden` on pods/log (if forbidden, add explicit `rbac.rules` for
   `pods`,`pods/log`,`namespaces`,`nodes` — chart default RBAC is the fallback).
4. discovery Grafana → Loki, query `{cluster="pastelariadev"}` returns pod logs.
5. etcd: `ls /bulk/k3s-etcd-snapshots/cp-*/` populates within a snapshot cycle
   (or force one: `k3s etcd-snapshot save` on a CP).
6. Bonus: discovery Grafana → Prometheus, `up{instance=~".*"}` now shows host
   metrics flowing (the `:9090` fix) — verify after deploying discovery too.
