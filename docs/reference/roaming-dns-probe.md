# Roaming DNS and ingress probe

**Status:** IaC adoption complete; desktop PR #377 merged; candidate built on Orion and delivered through signed cache to Discovery. Host activation remains pending.

## Outcome and use

Human seed: “do all but 4”; accepted improvements 1, 2, 3 and 5. This is a manual diagnostic,
not a service, timer, remediation action, or replacement for gateway diagnostics.
Run on the roaming Linux client, not Discovery:

```sh
just verify-roaming-dns
# Direct invocation preserves machine-readable exit codes:
python3 scripts/verify-roaming-dns.py --off-lan
```

Python stdlib plus existing `ip`, `tailscale`, `dig`, `getent`, and `curl` suffice.
Reading Tailscale's netmap may need passwordless `sudo -n`; only that read is
elevated, using NixOS's sudo wrapper when present. No operator-setting changes.

Discovery's LAN and stable tailnet IPs and ingress zone come from committed
[`fleet.json`](../../fleet.json). The four exact `/32`s match Discovery's
[`networking.nix`](../../modules/hosts/discovery/networking.nix): Discovery and
home subnet offsets 1, 2, and 4. The home `/24` is derived from Discovery's address.

## Acceptance and boundaries

Explicit `--off-lan` intent is mandatory. Independent main-table physical
connected subnet/source and matching default establish roaming. Before choosing
that uplink, independently reject home-prefix overlap in any active non-Tailscale
IPv4 address or main-table connected route, regardless of route protocol or sysfs
physical-device identity. Missing interface activity metadata is conservatively
treated as potentially active. A home-range virtual bridge/overlay can therefore
mean unavailable even when benign: ambiguity is intentional, not a successful
skip. Sysfs identity restricts only the candidate physical roaming uplink. Absent
uplink or multiple candidates are unavailable. Missing Discovery peer/route after
confirmed roaming remains a path failure, never environment unavailable.

Then require `tailscale status --json` to associate the committed stable tailnet
IP with exactly one peer whose `HostName` is exactly `discovery`; missing or wrong
hostname fails. A fully qualified MagicDNS `Name` is not required: exact HostName
plus stable IP suffices without a hard-coded suffix or duplicated node ID. This
does not replace the independently owned IaC control-plane identity guard.
Require that Discovery peer's netmap `AllowedIPs` to contain all four `/32`s, all four
policy-route lookups to use `tailscale0`, UDP and TCP DNS directly against Discovery
for LiteLLM, and system IPv4 resolution for both ingress names to return Discovery.
Normal TLS-verified, uncredentialed GETs require LiteLLM `/v1/models` status 401 and
AdGuard `/` status 302, both with Discovery as remote IP. Curl configuration and
proxies are bypassed; no address override, insecure TLS, or redirect following.
Bodies are discarded, not logged; no OAuth credentials or model completion.
Commands have 12-second deadlines, DNS one 3-second attempt per transport, HTTPS
8-second limits. Fail fast; success marker appears only after every layer passes.

| Direct script exit | Marker | Meaning |
|---|---|---|
| 0 | `ROAMING_DNS_OK` | Confirmed off-LAN; all checks passed |
| 1 | `ROAMING_DNS_FAILED` | Confirmed off-LAN; path check failed |
| 2 | `ROAMING_DNS_UNAVAILABLE` | No explicit intent or environment cannot establish off-LAN |

## Evidence, limits, and handover

On 2026-10-13, focused unittest first failed against the no-op baseline with
`AssertionError: 0 != 1` for missing route/DNS behavior. Independent review found
home secondary-address, static-route and bridge false passes, plus wrong peer
identity. Six added cases failed (`0 != 2` / `0 != 1`) before repairs. Normal and
optimized Python now pass; independent review confirms failure/unavailable
semantics. CI runs the probe suite and eight drift-pin cases; combined pytest
selection passes 38 tests. Lint, format, docs and diff checks pass.

The repaired probe independently passed on Endeavour's `wlo1`, physical subnet
`10.115.78.0/24`, source `.213`, gateway `.127`. A repeat caught TCP DNS failure
with exit 1 and no PASS; later direct TCP and full checks passed. Cause remains
unproven; acceptance/timeouts were unchanged. This proves client routes, DNS and
TLS ingress then—not infrastructure forwarding, inference, outage resilience or
future-network success. The reviewed draft is preserved in ignored harness
`roaming-dns-probe-reviewed-draft-1.md`; probe/test SHA-256 receipts are
`6bc85aa3c601fad8572d7d7abdc4c015a5f50929981f45beebb51777c9123557` and
`d8fe5d36bd7770e2eb2e03eab0f4387173a6aa9d7d9f6288f8e21aaba04c5ac9`.
On 2026-10-14, a fresh probe also passed from physical `192.168.1.5/24`, with
both expected HTTPS statuses and `.210` remote addresses.

## Published dependency and pending rollout

IaC [PR 133](https://github.com/ErikBPF/homelab-iac/pull/133) merged as
`d487d53ea4df11765054e13c75b5f41f00ece307`. Wired Orion applied one existing DNS
rule import with zero remote mutations; native identity guard passes and both
DNS/ACL follow-up plans exit 0. Complete DNS, ACL and route readback is unchanged.

Consumer URL and original/locked revisions now pin that exact SHA, replacing
`50b47432b80ce15fd8e6d27ccbe4763ab558cc7f`, retaining non-flake semantics.
`just --no-dotenv update-input homelab-iac` calculated
`sha256-/N3pmdGeK51s17nLtZMRZixqCMg9AgA8fKRU5DpOLHc=`; other lock nodes and root
metadata are unchanged. Pin contract failed on old URL (7 passed, 1 failed), then
all eight passed. Targeted non-building eval resolves new source and drift
executable; advertisements/client preferences remain unchanged.

Same input also supplies Telstar capture code; existing no-restart/no-stop guards
remain. No Python guard or runtime PATH addition is needed. Admin ACL tightening
is excluded. Desktop [PR #377](https://github.com/ErikBPF/desktop-nixos/pull/377)
merged as `2f33efc7990954283aff401f8deef91593b5f000`; eleven CI checks passed.
Targeted Discovery dry-build passed. Its later client-controlled build timed out;
the user then specified “build packages on orion and send to discovery. Orion is
the official cache”. Exact evaluated derivation was transferred to Orion, built
there with other builders disabled, and rooted at
`/var/tmp/discovery-tailscale-hardening-2f33efc`. No source or package compilation
ran on Discovery.

## Official cache delivery receipt

Candidate output:
`/nix/store/mm8sz6m9qgmcifb7l0yzp3d56zwjs3kv-nixos-system-discovery-26.11.20260922.6774f7b`.
Orion's [cache module](../../modules/services/nix-cache.nix) serves its signed local
store directly; there is no separate upload step. Discovery reached the declared
LAN cache, obtained candidate's `Sig: orion:`, and successfully verified one
trusted signature before copying the full closure:

```sh
# Run on Discovery; keep signature verification and existing cache trust.
nix store verify --store http://192.168.10.220:5000 --no-contents --sigs-needed 1 \
  /nix/store/mm8sz6m9qgmcifb7l0yzp3d56zwjs3kv-nixos-system-discovery-26.11.20260922.6774f7b
nix copy --from http://192.168.10.220:5000 --option require-sigs true \
  --out-link /var/tmp/discovery-tailscale-hardening-2f33efc \
  /nix/store/mm8sz6m9qgmcifb7l0yzp3d56zwjs3kv-nixos-system-discovery-26.11.20260922.6774f7b
```

Transfer completed: sixteen missing paths fetched directly from Orion. Both hosts
have identical complete closure metadata (NAR hashes, sizes and references) for
all 1,878 paths, and candidate is rooted on both. Discovery's running/profile/
booted paths remain unchanged after delivery. `nix store diff-closures` against
running system reports only `source: 190.0 KiB`; this does not replace unit diff
or activation checks. Fresh comparison of resolved systemd directories found only
the drift and Home Manager service links differ; their activation effects and
rollback baseline still need verification. Comparing unresolved directory symlinks
initially inspected only the root link, not units; no acceptance relied on it.
Store copies do not activate candidate. Generation 129
(`v6rpgw`) coincided with a successful
unattended boot-staging invocation; running (`iacvrg`) and booted (`d8plj2`)
systems remain distinct. User authorized preserving/superseding 129 and wrapping
unchanged running OS for rollback, but wrapper preparation was cancelled. Full
closure/unit diff, exclusive-window and rollback gates still precede activation;
this task has changed no system profile. Cache delivery is not checker health.
Stopping probe is its recovery. Pin recovery reverts the input pin; host rollout
requires an explicit rollback baseline and cannot undo mutable data.
