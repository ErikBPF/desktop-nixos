# `homelab-iac` — Declarative, Git-Versioned UniFi (UDM) Config via OpenTofu

**Date:** 2026-06-20
**Status:** **IMPLEMENTED** — repo `git@github.com:ErikBPF/homelab-iac.git`
(local `~/Documents/erik/homelab-iac`, symlink `references/repos/homelab-iac`).
Phase-1 import done: networks (Default, Main), WLANs (×3), DNS (×2),
reservations (×22) all plan zero-diff. **§5 below is the original sketch and is
superseded by the as-built**: Terragrunt + per-stack modules (not flat `.tf`),
`.env`/dotenv + OpenTofu state encryption (not sops), local encrypted state.
See the repo `README.md` for the real layout.
**Owner:** erik
**Target device:** UniFi Dream Machine Pro / SE, Network app **9.x** (API-key auth)
**Tooling:** OpenTofu + `filipowm/terraform-provider-unifi`
**Related:** sister-repo pattern follows `servarr` / `hermes-flake`.

> Naming: keep it boring and literal — `homelab-iac` (UniFi + Terraform/OpenTofu).
> Not a fleet host, so the spacecraft naming scheme does not apply.

---

## 1. Goal

Make the router's **controller-level configuration** declarative and
git-versioned — a "Terraform for the network." Source of truth moves from the
UniFi web UI (imperative, clicky, un-reviewable) to a versioned OpenTofu config
that is diffable, peer-reviewable, and reproducible.

**Phase 0 first (locked decision): import current state, change nothing.**
The first deliverable reflects the *existing* live config into code and reaches
a clean `tofu plan` (no diff). Only after that do we make changes through code.

### Responsibility boundary (the core principle)

| Layer | Owner | Where it lives |
|---|---|---|
| Network/controller config — VLANs, WLANs, firewall, port-forwards, DNS, DHCP reservations | **OpenTofu** (`homelab-iac`) | new sister repo |
| UniFiOS device firmware + the controller app itself | **Ubiquiti** (UI updates) | the device |
| UniFiOS-level / on-boot persistence (custom scripts) | **out of scope** (see §7) | n/a today |
| Host OS / NixOS fleet | **this flake** | `desktop-nixos` (unchanged) |

The UDM is **not** becoming a NixOS host. This proposal manages the *config the
controller exposes via its API*, the same surface the web UI drives.

---

## 2. Why (problem statement)

`TODO(erik)`: state the actual pain in your words. Candidate points to keep or cut:

- Router config is the least-reproducible part of the homelab — everything else
  (hosts via this flake, containers via `servarr`, HA via `home-assistant-config`)
  is already code; the network is the gap.
- No review trail for firewall / VLAN / port-forward changes; no diff, no blame.
- A factory reset or device RMA today means rebuilding config from memory.
- `TODO(erik)`: anything else?

---

## 3. Grounding (web research, 2026-06-20)

Three viable approaches exist; this proposal picks **OpenTofu + provider** (§4).

1. **`filipowm/terraform-provider-unifi`** — active maintained fork of the
   original `paultyng` provider. v1.0.0 (Mar 2025), built on the `go-unifi` SDK.
   Manages networks, WLANs, firewall rules, port-forwarding, DNS records, users.
   Controller **6.x+**; compatible with UDM / UDM-Pro / UCG. **API-key auth**
   on controller **≥ 9.0.108** (else username/password).
2. **`paultyng/terraform-provider-unifi`** (original) — effectively v6-era /
   semi-stale; a `ubiquiti-community` fork also exists. Not chosen.
3. **Official UniFi Network API** (developer.ui.com, v9.x) + official
   `ubiquiti.unifi_api` Ansible collection — officially supported and stable,
   but **narrower write scope** for full config-as-code today. Best long-term
   bet for stability; not yet a full replacement for the provider's coverage.

**Key caveats (apply to any provider-based approach):**

- The provider drives the **private/internal** controller API (reverse-engineered
  via `go-unifi`). It can **drift / break across controller updates** — pin the
  provider version and re-test after each Network-app upgrade.
- **Wired connection required** to apply changes — editing Wi-Fi/VLAN config over
  Wi-Fi can disconnect you mid-apply. Apply from a LAN-attached host.
- Not everything in the UI is exposed; some settings have no resource. Expect a
  subset, not 100% coverage. `TODO(erik)`: confirm coverage of the specific
  things you care about during Phase 0 import.

Sources:
- [filipowm/terraform-provider-unifi](https://github.com/filipowm/terraform-provider-unifi)
- [filipowm/unifi — Terraform Registry](https://registry.terraform.io/providers/filipowm/unifi/latest/docs)
- [paultyng/terraform-provider-unifi](https://github.com/paultyng/terraform-provider-unifi)
- [Official UniFi Network API — Ansible guide](https://developer.ui.com/network/v9.1.120/quick_start.ansible)

---

## 4. Decision (locked) + rationale

| Decision | Choice | Why |
|---|---|---|
| Tool | **OpenTofu** | FOSS (MPL) fork of Terraform — fits the nix/FOSS repo ethos; CLI-compatible with the provider. |
| Provider | **`filipowm/terraform-provider-unifi`** | The only actively-maintained option with broad config coverage. |
| Auth | **API key** (Network app 9.x) | No password in state/plan; scoped, revocable. |
| First milestone | **Import current state, zero diff** | De-risk: prove read + import before any change. |
| Location | **New sister repo `homelab-iac`** | Matches `servarr`/`hermes-flake` pattern; keeps IaC state out of the nix flake. |

`TODO(erik)`: confirm or override any row above. (Selected via proposal intake;
restated here so the doc stands alone.)

---

## 5. Architecture

```
unifi-tf/                      (new sister repo, symlinked → references/repos/unifi-tf)
├── main.tf                    provider + backend config
├── networks.tf                VLANs / networks
├── wlans.tf                   SSIDs
├── firewall.tf                firewall rules + groups
├── port_forwards.tf           port-forward rules
├── dns.tf                     local DNS records
├── reservations.tf            DHCP fixed-IP leases
├── variables.tf
├── terraform.tfvars           non-secret vars (committed)
├── secrets.sops.yaml          API key + controller URL (sops-encrypted)
├── .gitignore                 *.tfstate*, .terraform/, *.tfvars w/ secrets
├── Justfile                   plan / apply / import recipes (sops-wrapped)
└── README.md
```

### State backend
`TODO(erik)`: decide. Options:
- **Local state, git-ignored, sops-backed-up** — simplest; single operator (you).
  `*.tfstate` never committed; optionally encrypt a copy into the repo.
- **Remote backend** (e.g. an S3-compatible bucket on the homelab) — overkill for
  one operator but enables locking/history. Recommend **local** for v1.

### Secrets flow (repo convention)
- API key + controller URL live in `secrets.sops.yaml` (sops/age, same as the
  rest of the homelab). **Never** plaintext, never in state-in-git.
- Justfile recipes `sops exec-env` the secrets into `TF_VAR_*` at plan/apply time.
- `.env`-style files excluded by `.gitignore` and the universal commit rules.

### Run mechanism
- Manual, operator-driven: `just plan` / `just apply` from a **wired** host on the
  LAN (per §3 caveat). No CI auto-apply — network changes are too blast-radius-y
  for unattended runs. `TODO(erik)`: agree? CI could run `plan` as a dry-check
  on PR without `apply`.

---

## 6. Plan (phased, each with a verify step)

| Phase | Work | Verify |
|---|---|---|
| **0. Bootstrap** | Create `homelab-iac` repo; generate Network-app API key; write `main.tf` provider block; `tofu init`. | `tofu providers` resolves; auth succeeds against controller (a trivial data-source read). |
| **1. Import** | `tofu import` existing networks/WLANs/firewall/port-forwards/DNS/reservations into code. Hand-write the matching resource blocks. | **`tofu plan` shows zero diff** against live config. This is the gate. |
| **2. Wire into repo** | Symlink `references/repos/unifi-tf`; document in `desktop-nixos` CLAUDE.md cross-repo section + coupling map; sops-encrypt secrets. | Symlink resolves; `sops -d` round-trips; `just plan` runs clean. |
| **3. First real change** | Make one small, reversible change **through code** (e.g. add a DNS record). | `tofu apply` succeeds; change visible in UI; `tofu plan` clean after. |
| **4. Operate** | Move ongoing network changes to code; `plan`→review→`apply` workflow. | Each change is a reviewed commit + clean post-apply plan. |

`TODO(erik)`: confirm scope per phase. Locked decision is **import-first**;
Phase 3+ scope (which subsystems to actively manage) is yours to set.

---

## 7. Explicitly out of scope (v1)

- **UniFiOS-level / on-boot persistence** (custom scripts via `udm-utils` /
  `on_boot.d`). Different mechanism, survives firmware updates poorly, higher
  risk. Park it; revisit only if a concrete need appears.
- **Device firmware / controller-app version management** — stays manual via UI.
- **Multi-site / multi-controller** — single UDM only.
- Making the UDM a NixOS host — not happening.

---

## 8. Risks & mitigations

| Risk | Mitigation |
|---|---|
| Private API breaks on controller upgrade | Pin provider version; re-run `plan` after every Network-app upgrade before trusting `apply`. |
| Lock-out mid-apply over Wi-Fi | Apply only from a **wired** LAN host (hard rule in README + Justfile preflight). |
| State drift (someone clicks in UI) | `tofu plan` as a periodic drift check; treat UI edits as exceptions to re-import. |
| State file leaks secrets | Local state git-ignored; secrets via sops; never commit `*.tfstate`. |
| Provider abandons / official API matures | Approach #3 (official API + Ansible) is the documented fallback; revisit at next major controller version. |
| Incomplete coverage (UI setting has no resource) | Discovered in Phase 1 import; document the gaps, keep those few settings manual. |

---

## 9. Open questions (`TODO(erik)`)

1. State backend: local vs remote? (Recommendation: local for v1.)
2. CI: run `plan` as a PR dry-check, or fully manual? (Recommendation: PR `plan`, manual `apply`.)
3. Exact Network-app version on the device — confirm ≥ 9.0.108 for API-key auth.
4. Which subsystems to *actively* manage post-import (firewall? WLANs only? all)?
5. Repo visibility — private remote, or local-only git?

---

## 10. Acceptance (definition of done for v1)

- `homelab-iac` repo exists, symlinked under `references/repos/`, documented in the
  cross-repo + coupling-map sections of `desktop-nixos/CLAUDE.md`.
- All targeted existing config is imported; **`tofu plan` shows zero diff**.
- Secrets are sops-encrypted; no plaintext credentials or `*.tfstate` in git.
- At least one change has been made end-to-end through code (Phase 3).
- README documents the wired-apply rule and the `just plan`/`apply` workflow.
