# Shared sccache compiler cache on orion (tailnet)

**Status:** The original cache was observed live on 2026-06-30. The accepted
2026-10-29 follow-up restricts remote writers to Endeavour, laptop and Kepler;
source and disposable HTTP verification are prepared, deployment unverified.
Current source enables the client on Endeavour. The June observations below
remain historical. Cache mode keeps compilation local; `sccache-dist` remains
deferred.

## Problem

Dev-loop `cargo build` on the laptop recompiles crates that another fleet host —
or the same host on a clean tree — already built. Nix's build offload
(`distributed-builds.nix` → orion) only covers **Nix-packaged** Rust
(`buildRustPackage`/crane); it does nothing for interactive `cargo`. We wanted a
shared compiler cache so repeated cargo builds reuse artifacts, without disturbing
the Nix path.

## Decision

1. **Cache mode, not `sccache-dist`.** sccache still runs `rustc` locally; orion
   only *stores/serves* cached objects. A cache miss or an unreachable orion
   (off-tailnet, DNS fail, timeout) falls back to a local compile automatically —
   the "fallback to local" requirement is inherent to cache mode. True CPU offload
   (`sccache-dist`) is deferred (see below) because it is finicky with Nix
   toolchains (sandboxed rustc links to `/nix/store` paths).
2. **WebDAV over redis.** A compiler cache is disk-shaped (multi-GB); redis would
   pin it in orion RAM. WebDAV is disk-backed and NixOS-native — nginx's
   `http_dav_module` (compiled into nixpkgs' default nginx), one vhost.
3. **`listen 0.0.0.0:4321`, gated by the `tailscale0` firewall only.** 4321 is
   opened solely on `tailscale0`; LAN/WAN are dropped (not in the global
   `allowedTCPPorts`). Binding `0.0.0.0` rather than orion's tailnet IP sidesteps
   the tailscale0 IP-assignment boot race that forced the retry loop in
   `discovery/vault.nix`. The trust boundary is the tailnet.
4. **Server-side writer authorization.** Nginx permits mutations only from the
   fleet addresses of Endeavour and Kepler and the existing legacy laptop
   identity in `fleet.tailnetPeers`, plus trusted local loopback
   maintenance. GET/HEAD retain existing read reachability. There is no
   application token; the writer boundary depends on tailnet source identity.
5. **Endpoint = orion tailnet IP from the fleet SSOT** (`http://100.72.85.73:4321/`),
   pulled from `fleet.hosts.orion.tailscaleIp` in `modules/meta.nix` — no DNS
   dependency, single source.
6. **Client use remains opt-in** via `programs.sccacheClient.enable`. Broad
   tailnet reachability does not grant writes: the method restriction is at
   the server, including when Discovery reaches it through a wildcard grant.

## What shipped on 2026-06-30

- `modules/services/sccache.nix` — two dendritic modules:
  - `sccache-cache` (server): nginx WebDAV vhost on `0.0.0.0:4321`, root
    `/var/cache/sccache-shared` (tmpfiles `nginx:nginx 0750`), firewall opens 4321
    on `tailscale0`. Enabled on **orion**.
  - `sccache-client`: installs `pkgs.sccache`, sets `RUSTC_WRAPPER=sccache` +
    `SCCACHE_WEBDAV_ENDPOINT` via `environment.sessionVariables`. Opt-in; enabled
    on **laptop**. Asserts `orion.tailscaleIp != null`.
- `modules/meta.nix` — backfilled `tailscaleIp` for orion/kepler/pathfinder/
  archinaut/voyager/laptop (orion's is the cache endpoint); `fleet.json`
  regenerated.
- `homelab-iac` `tailscale/acl/policy.hujson` — ACL rule 11 opens `orion:4321` to
  all tailnet hosts (+ tests). Owned there per SRP (Tailscale ACL = homelab-iac).

`RUSTC_WRAPPER` in the login-shell env does **not** leak into Nix's sandboxed
builds, so the Nix build-offload path is untouched — only interactive cargo hits
the cache.

## Historical verification on 2026-06-30

- orion: `nginx` active, `0.0.0.0:4321`, `/var/cache/sccache-shared` present
  (`nginx:nginx 0750`); host firewall rule `nixos-fw -i tailscale0 --dport 4321
  accept`; orion→self:4321 = HTTP 403 (bare GET on an empty dav dir = nginx alive).
- Tailnet reachability after the ACL apply: laptop→orion:4321 = 403; kepler
  (server)→orion:4321 = 403. `orion:4321` was a timeout **before** the ACL rule,
  confirming the ACL (not the host firewall) was the gate.
- End-to-end cache write (a real `cargo build` populating the cache) pends a build
  in a fresh login shell — `sessionVariables` apply on next login.

## Writer restriction follow-up on 2026-10-29

The [accepted behavior](../behaviors/sccache-writers/behavior.md) and
[test contract](../behaviors/sccache-writers/test-contract.md) preserve reads,
endpoint, firewall port and local maintenance. An isolated Nix evaluation
renders the actual module with synthetic fleet addresses. A disposable Nginx
fixture checks permitted DAV operations, rejected remote mutations and rejected
forwarding-header spoofing. These checks are wired into `check.yml`.

No live cache, deployment, real Cargo build or host firewall was exercised by
this follow-up. All accepted writers share one trusted cache namespace; one
compromised writer can still poison entries read by other consumers. Tailnet
address changes require the corresponding fleet update and Nginx deployment.
The legacy laptop is no longer a managed fleet host. Its accepted IaC address
is declared once in `modules/meta.nix` under `fleet.tailnetPeers` and exported
in `fleet.json`; updating it requires `just fleet-json`. This keeps
`fleet.hosts`, upgrade targets and the physical inventory unchanged. The cache
selects the laptop peer by name, so adding another peer does not grant writes.
Static metadata does not prove live ownership; reconcile effective identities
before rollout.
If writer authorization breaks, compile locally while correcting the mapping;
do not automatically reopen remote writes.

## Deferred — `sccache-dist` (CPU offload)

If cold-build CPU on the laptop still hurts, add `sccache-dist scheduler` + `server`
units on orion and a `[dist]` block on clients. The client env above stays; the
new cost is toolchain packaging + a bubblewrap sandbox that must carry the Nix
rustc closure. Not done — the cache is expected to cover the common case first.
