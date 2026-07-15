# Shared sccache compiler cache on orion (tailnet)

**Status:** ✅ Implemented (2026-06-30) — disk-backed sccache WebDAV cache live on
orion, reachable fleet-wide over the tailnet; client opt-in shipped and enabled on
laptop. Cache mode only (compiles stay local); `sccache-dist` CPU offload is the
deferred upgrade below.

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
4. **No app auth.** Matches repo posture (vault binds the tailnet, ACL-gated). Add
   `SCCACHE_WEBDAV_TOKEN` later if wanted.
5. **Endpoint = orion tailnet IP from the fleet SSOT** (`http://100.72.85.73:4321/`),
   pulled from `fleet.hosts.orion.tailscaleIp` in `modules/meta.nix` — no DNS
   dependency, single source.
6. **Servers may share the cache too.** The tailnet ACL grant is broad
   (`src ["*"] → orion:4321`); actual use stays opt-in per host via
   `programs.sccacheClient.enable`.

## What shipped

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

## Verification

- orion: `nginx` active, `0.0.0.0:4321`, `/var/cache/sccache-shared` present
  (`nginx:nginx 0750`); host firewall rule `nixos-fw -i tailscale0 --dport 4321
  accept`; orion→self:4321 = HTTP 403 (bare GET on an empty dav dir = nginx alive).
- Tailnet reachability after the ACL apply: laptop→orion:4321 = 403; kepler
  (server)→orion:4321 = 403. `orion:4321` was a timeout **before** the ACL rule,
  confirming the ACL (not the host firewall) was the gate.
- End-to-end cache write (a real `cargo build` populating the cache) pends a build
  in a fresh login shell — `sessionVariables` apply on next login.

## Deferred — `sccache-dist` (CPU offload)

If cold-build CPU on the laptop still hurts, add `sccache-dist scheduler` + `server`
units on orion and a `[dist]` block on clients. The client env above stays; the
new cost is toolchain packaging + a bubblewrap sandbox that must carry the Nix
rustc closure. Not done — the cache is expected to cover the common case first.
