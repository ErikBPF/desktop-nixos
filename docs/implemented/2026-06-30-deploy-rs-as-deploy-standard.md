# deploy-rs as the fleet remote-deploy standard

**Status:** Implemented (2026-06-30). deploy-rs is the fleet's remote-switch
standard and the two-phase toolchain (install + switch) is live: `modules/deploy-rs.nix`
exposes `flake.deploy.nodes`; every `switch-<host>` delegates to `deploy-rs`
(GPU hosts via `deploy-rs-boot` + reboot); `provision <host> <target>` is the
generic first-install. Magic rollback was proven on a throwaway VM and on the
real voyager host. All [§9](#9-open-questions) judgment calls were decided
(replace `switch-<host>`; pilot = voyager; kepler = boot+reboot on its window;
`magicRollback` per reach-path; fleet-wide OAuth by role). Rollout:
orion/discovery/kepler switched (GPU hosts rebooted — drivers matched);
archinaut in progress; telstar pending Oracle A1 capacity. Kept as the as-built
record.
**Audience:** Maintainer of `desktop-nixos` (fleet operator).

## 1. Context — how deploys work today

The fleet has two distinct remote operations, both driven from `justfile`:

- **First install** — `nixos-anywhere` (`deploy-orion`, `deploy-discovery`,
  `deploy-kepler`, the generic `nixos-anywhere` recipe) or `nixos-infect`
  (`infect-voyager`). These partition/convert a fresh box and stage the sops age
  key under `/var/lib/sops-staging/`.
- **Subsequent switches** — `nixos-rebuild switch --flake .#<host>` with
  `--target-host erik@<ip>`, `--use-substitutes`, `--sudo`, over SSH on port
  **2222**, via the generic `deploy` recipe and the per-host `switch-<host>`
  wrappers. `switch-all` fans `discovery`/`orion`/`pathfinder` out in parallel;
  `kepler` is deliberately excluded ("deploy on its own window so the AI serving
  stack isn't restarted as a side effect"). aarch64 hosts (`archinaut`) and the
  1 GB `voyager` add `--build-host erik@<orion-ip>` so the closure is *built* on
  Orion (the `orion_builder` offload, x86 + aarch64 via binfmt) and only
  *activated* on the target.

**The gap:** `nixos-rebuild switch --target-host` activates the new generation
and exits. If the new config breaks networking, `sshd`, the firewall, or
Tailscale, the operator's *next* SSH attempt fails and there is **no automatic
rollback** — recovery is manual (serial console, OCI web console, physical
access, or a recreate). For LAN hosts with a keyboard nearby this is annoying;
for a headless cloud micro it is an outage.

## 2. Motivation — the voyager episode

`voyager` is a 1 GB x86 Oracle Cloud "always-free" micro at `64.181.174.237`.
Provisioning it was repeatedly painful precisely because a bad remote state has
no cheap recovery path:

- `nixos-anywhere`'s `kexec --load` **OOMs** on 1 GB, so the kexec install path
  is unusable.
- The fallback is `nixos-infect` converting the stock Ubuntu image in place
  (hybrid GRUB-UEFI, reusing Ubuntu's GPT layout), then `switch-voyager`
  converging to the full flake.
- During that work the box went **unreachable** more than once, each time
  needing the **Oracle OCI serial/web console** — or, in the worst case, a
  destroy-and-recreate of the instance — to get back in.

A switch that changes `networking`, the firewall, `sshd`, or the Tailscale unit
can brick remote access on *any* headless host, but voyager made the cost
concrete. deploy-rs's **magic rollback** is the direct mitigation: after
activating the new profile it opens a fresh SSH connection back to confirm the
host is still reachable; if that confirmation fails within a timeout it
**rolls the host back to the previous generation automatically**. The operator
gets the old, working generation instead of a dead box.

## 3. What deploy-rs is

[deploy-rs](https://github.com/serokell/deploy-rs) (serokell) is a small Rust
multi-profile Nix deploy tool. Relevant properties:

- **Build host / target host split** — `remoteBuild` / build-on-target or
  build-locally-and-copy; works with our Orion offload model.
- **Magic rollback** (default on) — activate → SSH connectivity re-check →
  auto-revert on failure. Can be disabled per-node (`magicRollback = false;`).
- **`autoRollback`** — roll back if activation itself fails (separate from the
  connectivity check).
- **`activationTimeout` / `confirmTimeout`** — bound how long the connectivity
  confirmation waits.
- **`sshUser` / `user` / `sshOpts`** — maps cleanly onto `erik@host -p 2222`
  and our `--sudo` model (`user` = the activation user, defaults to root via
  sudo).
- Ships `deploy-rs.lib.<system>.activate.nixos` (the activation wrapper) and a
  `deploy-rs.lib.<system>.deployChecks` helper that validates the `deploy`
  output.

It is **not** an installer — it switches an already-running NixOS host. So it
*complements* `nixos-anywhere`/`nixos-infect` (which keep owning first install),
it does not replace them.

## 4. How deploy-rs integrates in this dendritic flake-parts flake

deploy-rs expects a **top-level flake output** `deploy.nodes.<name>` and exposes
`checks` via `deploy-rs.lib.<system>.deployChecks`. In a plain flake you'd write
`outputs.deploy`. In **this** flake the entry point is
`flake-parts.lib.mkFlake + import-tree ./modules` (`flake.nix`), so every
`modules/*.nix` file is a flake-parts module and there are no aggregator import
lists ([dendritic-contract.md](../reference/dendritic-contract.md)). The
mechanics that fit that contract:

1. **Add the input** (`flake.nix`), following nixpkgs:

   ```nix
   deploy-rs = {
     url = "github:serokell/deploy-rs";
     inputs.nixpkgs.follows = "nixpkgs";
   };
   ```

2. **Register a new flake-parts module** — e.g. `modules/deploy-rs.nix` — that
   sets the top-level `flake.deploy` output and merges deploy-rs's checks. In
   flake-parts, top-level outputs are set under `flake.*` and per-system outputs
   under `perSystem`. A first cut:

   ```nix
   { inputs, config, lib, ... }:
   let
     # SSOT for addressing already lives in fleet.json / fleet.* (meta.nix).
     fleet = config.flake.fleet or (builtins.fromJSON (builtins.readFile ../fleet.json));
     mkNode = host: hostname: {
       inherit hostname;
       sshUser = "erik";
       user = "root";                       # activate via sudo, like --sudo today
       sshOpts = [ "-p" "2222" ];
       magicRollback = true;
       profiles.system = {
         path = inputs.deploy-rs.lib.x86_64-linux.activate.nixos
           config.flake.nixosConfigurations.${host};
       };
     };
   in {
     flake.deploy.nodes = {
       voyager    = mkNode "voyager"    "64.181.174.237";
       discovery  = mkNode "discovery"  fleet.hosts.discovery.ip;
       orion      = mkNode "orion"      fleet.hosts.orion.ip;
       pathfinder = mkNode "pathfinder" fleet.hosts.pathfinder.ip;
       kepler     = mkNode "kepler"     fleet.hosts.kepler.ip;
       # archinaut is aarch64 → activate.nixos must come from
       # deploy-rs.lib.aarch64-linux; closure still builds on orion (binfmt).
     };

     # Surface deploy-rs's own sanity checks into `nix flake check`.
     # perSystem.checks = inputs.deploy-rs.lib.${system}.deployChecks config.flake.deploy;
   };
   ```

   Sketch only — the exact wiring of `deployChecks` into `perSystem.checks`,
   and whether `activate.nixos` is chosen per-host-system, needs to be worked
   out against the real flake during the pilot. `deploy-rs.lib` keys off
   `deploy.nodes`, so the output must be named exactly `flake.deploy`.

3. **Build on Orion.** deploy-rs honours the same Nix builder machinery, so the
   `orion_builder` offload (or per-node `remoteBuild`) keeps closures off the
   1 GB / aarch64 targets, exactly as `--build-host` does today.

4. **Wrap in `just`** so the [channelled-remote-action policy](../../CLAUDE.md)
   holds — every remote touch still goes through a documented recipe:

   ```just
   # Subsequent switch with magic rollback (build on orion, activate on target).
   deploy-rs target:
       nix run github:serokell/deploy-rs -- .#{{target}} \
           --skip-checks \
           -- --option builders "{{orion_builder}}" \
              --option builders-use-substitutes true
   ```

   (Flag set is illustrative; pin deploy-rs from the flake input rather than
   `nix run github:…` once the input exists.)

This keeps the SSOT intact: addressing still flows from `fleet.json`
(`fleet.*` in `meta.nix`), and `deploy.nodes` reads it rather than duplicating
IPs.

## 5. Proposal

1. Add `deploy-rs` as a flake input (nixpkgs-following).
2. Add one flake-parts module exposing `flake.deploy.nodes.<host>` for the
   **remote** fleet (`voyager`, `discovery`, `orion`, `pathfinder`, `kepler`,
   `archinaut`). `laptop` is local/roaming — out of scope. The `homeassistant`
   appliance is HAOS, not NixOS managed here — out of scope.
3. Keep `nixos-anywhere` / `nixos-infect` as the **first-install** path. deploy-rs
   is strictly for *subsequent* switches.
4. Add a `just deploy-rs <host>` recipe (and decide replace-vs-complement for
   `switch-<host>` — [§9](#9-open-questions)).
5. Enable `magicRollback = true` on hosts where rollback is meaningful (precious
   / hard-to-reach), with a sensible `activationTimeout`. Be deliberate about
   hosts whose first-boot services are slow (see [§7](#7-tradeoffs--costs)).

## 6. Migration plan (phased, per-host, low-risk)

| Phase | Action | Verify |
|-------|--------|--------|
| 0 | Add input + `modules/deploy-rs.nix`; `git add`; `nix flake check`, `just dry-all` | flake evaluates, `deploy` output present, no host closure changes |
| 1 | Pilot one host via `just deploy-rs <host>` alongside the existing `switch-<host>` (no removal yet) | host switches; deliberately deploy a known-bad networking change and confirm magic rollback restores SSH |
| 2 | Roll out to the rest of the remote fleet one host at a time | per-host post-switch `just verify <host>` green |
| 3 | Decide `switch-<host>` fate (alias to `deploy-rs`, or keep both) and update `switch-all` accordingly | `switch-all` still deploys its set; docs/recipe agree |

**Escape hatch:** the old `switch-<host>` / `deploy` recipes stay until Phase 3
explicitly retires them, so reverting is "use the old recipe." deploy-rs adds an
output and a recipe; it changes no host config, so Phase 0–1 are reversible by
dropping the input.

## 7. Tradeoffs & costs

- **New input + closure.** One more flake input (Rust tool) in `flake.lock` and
  the dev closure. Modest, nixpkgs-following.
- **Learning curve.** New CLI/output shape vs muscle-memory `nixos-rebuild`.
- **sops-nix first-boot race (flag for the human).** sops-nix decrypts secrets
  *during activation*, and on this fleet the age key is staged at
  `/var/lib/sops-staging/` and the **Tailscale auth key + compose `.env`** come
  from sops. If a host's reachability (esp. a Tailscale-only path) depends on a
  unit that only comes up *after* sops decryption + service start, magic
  rollback's connectivity check could fire **before** the host is legitimately
  reachable and roll back a *good* deploy. `activationTimeout`/`confirmTimeout`
  must be tuned to the slowest reachability-critical unit per host, or
  magicRollback disabled where the steady-state reachability path is itself
  brought up by a slow post-activation service. This needs measurement during
  the pilot, not a guess.
- **`--sudo` / ssh-as-`erik@2222`.** Maps to `sshUser = "erik"`, `user = "root"`,
  `sshOpts = ["-p" "2222"]`. The `erik` account already has the sudo rights
  `--sudo` relies on; deploy-rs uses the same path. The `voyager` first-switch
  quirk (initially `root@22`, then `erik@2222`) is a *first-install* concern and
  stays with `infect-voyager` + the first `switch-voyager` — deploy-rs only
  takes over once the host is in steady state at `erik@2222`.
- **Rollback value is uneven.** `voyager` is free and recreatable, so the
  *catastrophic* cost of a brick is lower there than on `kepler` (AI serving) or
  `discovery` (ingress/Vault). Honestly: the strongest rollback case is the
  hosts we'd *hate* to lose, not the throwaway — though voyager is the best
  *low-stakes pilot* precisely because bricking it costs nothing. Pilot value
  and production value point at different hosts; that's a deliberate tension.
- **kepler's deploy window.** kepler is excluded from `switch-all` so the AI
  stack isn't restarted as a side effect. deploy-rs doesn't change that; kepler
  would keep its own `just deploy-rs kepler` invocation on its own window.

## 8. Alternatives considered

- **Status quo (`nixos-rebuild --target-host`).** Zero new dependencies, already
  channelled through `just`. The one thing it cannot do is automatically recover
  a host that lost its own network/SSH on switch — the exact voyager failure
  mode. Keeping it is the do-nothing baseline.
- **colmena.** Mature multi-host deploy with parallelism and `--on` targeting;
  Hive-style config. But it wants its own `colmena` meta block / node model that
  doesn't map as cleanly onto our existing `configurations.nixos.<host>` +
  `fleet.json` SSOT, and its rollback story is weaker than deploy-rs's magic
  rollback. More tool surface for the feature we actually want (auto-revert).
- **NixOps.** Heaviest; state-file/backend model, history of churn across v1/v2.
  Overkill for an 8-host homelab and against the repo's "minimum that solves the
  problem" bias.

deploy-rs wins on a single axis that matters here: **magic rollback** with the
least new conceptual surface, while leaving first-install (`nixos-anywhere`) and
the Orion build offload untouched.

## 9. Open Questions

These are judgment calls for the maintainer — the draft does not pre-decide them:

1. **Fleet-wide vs precious-only.** Is automatic rollback worth a new input for
   the *whole* remote fleet, or only for hard-to-reach / high-value hosts
   (`voyager`, `kepler`, `discovery`)? A subset still adds the input but limits
   blast radius and tuning work.
2. **Pilot host.** `voyager` is the safest *low-stakes* pilot (free,
   recreatable, and the motivating failure), but its rollback *value* is lowest.
   Pilot on voyager for safety, or on a host where rollback would actually save
   us?
3. **Replace or complement `switch-<host>`.** Alias `switch-<host>` → deploy-rs
   (one mechanism, less drift), or keep both (escape hatch, more surface)?
4. **kepler's careful window.** Confirm deploy-rs on kepler stays a manual,
   out-of-`switch-all` invocation and that activation won't restart the AI stack
   any more than `nixos-rebuild switch` already does.
5. **magic-rollback timeout vs slow first-boot.** What `activationTimeout` /
   `confirmTimeout` per host avoids false rollbacks when reachability depends on
   a slow post-activation unit (sops decrypt → Tailscale/compose bring-up)? Or
   do we disable magicRollback on those and rely on `autoRollback`
   (activation-failure-only) instead?

## 10. Decision needed / next steps

- [ ] Maintainer answers [§9](#9-open-questions) (esp. scope, pilot, replace-vs-complement).
- [ ] If accepted: add the input + `modules/deploy-rs.nix`, `git add`, run
      `just dry-all` + `nix flake check` (Phase 0).
- [ ] Pilot one host with a deliberate known-bad switch to *prove* magic
      rollback restores SSH before trusting it (Phase 1).
- [ ] On success, graduate this doc to `docs/implemented/` and add the
      `just deploy-rs` recipe to the documented remote-action entry points.

## 11. Implementation — two-phase toolchain standard

Adopted after this RFC's pilot work. The fleet's deploy story is **two phases,
two tools**:

- **First install** (bare box → NixOS): `nixos-anywhere` *or* `nixos-infect`,
  chosen by host constraints (matrix below).
- **Subsequent switches** (running NixOS → new generation): **deploy-rs** with
  magic rollback, build offloaded to Orion.

### Install-method matrix (per host class)

| Host class | Tool | Why |
|---|---|---|
| LAN server / workstation (orion, discovery, kepler, pathfinder) | `nixos-anywhere` from NixOS ISO + disko | kexec works; full disko/LUKS control |
| A1 ARM cloud (telstar) | `nixos-anywhere` on Ubuntu entrypoint, build on Orion (binfmt) | A1 has RAM; kexec works |
| **1 GB x86 cloud (voyager)** | **`nixos-infect`-done-right** | kexec OOMs (contiguous-alloc, swap doesn't help); custom-image import blocked (`custom-image-count = 0` on free tier) |
| RPi (archinaut) | SD-image flash, built on Orion | no kexec on Pi |

**`nixos-infect`-done-right (the only x86-micro path)** — three non-obvious
requirements, each a failure we hit and fixed:
1. **virtio in initrd** — infect's generated config hardcodes
   `ata_piix/xen_blkfront/vmw_pvscsi`; OCI disk+NIC are virtio, so the boot is
   deaf without `virtio_pci/virtio_scsi/virtio_blk/virtio_net`.
2. **`PROVIDER=oracle doNetConf=y`** — Oracle isn't in infect's auto-list, so
   without it no network config is generated (unreachable even if it boots).
3. **don't interrupt the lustrate** — running `nixos-rebuild` mid-infect leaves
   a half-merged Ubuntu/NixOS hybrid; let infect run to completion and reboot
   itself, then converge with a normal switch.

### deploy-rs as the switch default — validated

`modules/deploy-rs.nix` exposes `flake.deploy.nodes.<host>`; `just deploy-rs
<host>` builds on Orion and activates with magic rollback. Per-host
`magicRollback` is set by reach-path (public-IP/LAN sshd = true; tailnet-only =
false to avoid racing the sops→Tailscale bring-up). `deployChecks` stays opt-in
(`flake.deployChecks`), never wired into `perSystem.checks`, so `nix flake
check`/CI cost is unchanged.

**Magic rollback proof (orion throwaway VM, `drtest`):** a normal switch
activated cleanly; a deliberately-broken generation
(`firewall.allowedTCPPorts = mkForce []`, blocking SSH) activated, the
post-activation reachability re-check timed out, and deploy-rs **auto-reverted
v2→v1**, restoring SSH. `drtest` (`modules/hosts/drtest/` + `drtest-vm-*`
recipes) is retained as the sanctioned deploy-rs smoke test.

### Shared OCI-guest profile

`profile-oci-guest` carries what's identical across Oracle cloud guests
(voyager, telstar): virtio initrd modules, `console=ttyS0` serial, and
GRUB `efiInstallAsRemovable` + `canTouchEfiVariables = false` (OCI VM NVRAM
isn't persisted, so the bootloader must sit at the removable fallback path).
Host modules keep only the layout-specific bits (fileSystems, disko-vs-in-place,
`efiSysMountPoint`, `configurationLimit`, `hostPlatform`).

### Hardening landed alongside this

- **`switch-voyager`/`switch-telstar` build offload** — switched from
  `--build-host erik@orion` (which inherited the target's `NIX_SSHOPTS` port and
  collided: `root 22` sent Orion's build connection to :22 instead of :2222) to
  `--option builders {{orion_builder}}`, the same offload the local `build`
  recipe uses. `NIX_SSHOPTS` now scopes to the target only.
- **`profile-oci-guest`** (above) de-duplicates the boot wiring.

### Open / follow-ups

- **Tailscale enrollment key** is the remaining reliability gap: the static sops
  `tailscale_authkey` expired and broke `tailscaled-autoconnect` on voyager.
  Durable fix is an OAuth-client secret in sops (no expiry) rather than a
  90-day-capped auth key; tracked separately.
- Canary the real fleet (voyager → discovery/orion/pathfinder → kepler on its
  own window → archinaut), then settle the §9 replace-vs-complement question.

### Cross-repo scope

deploy-rs / nixos-anywhere / nixos-infect are **host-OS** tools and belong to
`desktop-nixos` (and any future NixOS-host repo, which imports the same
`deploy-rs` module + recipe pattern). Workload repos keep their own delivery and
are out of scope: `servarr` = git-pull compose, `homelab-gitops` = Argo CD.
