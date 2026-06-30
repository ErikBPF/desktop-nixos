# OpenCode improvement — global + per-repo config

**Status:** Implemented (Phases G + L1-L3 + items 2+4). **Date:** 2026-06-29.
**Late edit 2026-06-30:** Nix flake scope changed — items 2+4 land a NixOS
opencode-client sops module in this flake (§ Implemented items). All claims
verified against docs.opencode.ai (Jun 29 2026 build).
**Scope:** two-layer opencode config — **global** (`~/.config/opencode/`, user
scope, follows you across machines) + **per-repo** (`opencode.json` at each
sister-repo root, project scope, ships in git). Plus durable sops-decrypted
keys on every desktop host (Item 2) and a scoped LiteLLM virtual key in place
of the master key (Item 4). All claims verified against docs.opencode.ai.

## Why

Today opencode is configured minimally: LiteLLM provider wired (`qwen-chat`,
`qwen-embed`), one `rtk.ts` plugin, read-allow only for
`~/.config/opencode/get-shit-done/*`. No MCPs, no policies, no `tui.json`, no
per-repo configs. Verified live (2026-06-29):

| Area | State | Source |
|------|-------|--------|
| Global config | `~/.config/opencode/opencode.json` — LiteLLM + rtk + minimal `read` allow | live file |
| Perms | `read`/`external_directory` allow only for `get-shit-done/*`; rest default `ask` | live file |
| MCP | none | live file |
| Policies | none | live file |
| `tui.json` | absent — default theme + silent | live dir |
| Plugins | `rtk.ts` only (wraps bash via `rtk rewrite`) | `plugins/` |
| Commands | 90+ `gsd-*` slash commands under `command/` | live dir |
| Agents | 30+ `gsd-*` agent definitions under `agents/` | live dir |
| Skills | `~/.agents/skills/` (40+) NOT loaded — opencode scans `.opencode/skills/` + `~/.config/opencode/skills/` | live dir |
| Per-repo configs | none in any sister repo | filesystem audit |
| Containerized serve | not running — local process on workstation | n/a |

Gaps:
1. **Hardening**: yolo is convenient but unprotected; non-yolo is annoying
   (every cmd prompts). Neither posture locked in. Secrets under
   `secrets/*.sops` and `.env.sops` reachable by `edit`/`bash`.
2. **Ergonomics**: default theme + silent; `tui.json` absent; no token-aware
   MCPs despite docs naming them standard tool surface.
3. **Per-repo strengths lost**: desktop-nixos loves nix search/options /
   just recipe MCPs; homelab-iac loves tofu; servarr loves compose-stack MCP.
   Global MCP=pollutes context for every project. Per-repo = right tool at
   right time.

## Scope split (the user's directive 2026-06-29)

Global config follows you across machines; per-repo config lives with the
code. Config layers auto-merge per docs (precedence: remote → global →
`OPENCODE_CONFIG` env → project → managed).

```
~/.config/opencode/opencode.json   ← GLOBAL: provider, base perms, policies, theme/attention
   ↳ merges ──▶   opencode.json    ← PER-REPO at each sister-repo root
                                ↑ each repo adds MCPs + perm extensions specific to that stack
```

---

## GLOBAL scope proposals `~/.config/opencode/`

### G1 — Permission guardrails (yolo + secrets deny)

Yolo `permission: "allow"` blanket; explicit `deny` for secrets + raw remote
deploys. Channel correct paths via `just` recipes (CLAUDE.md doctrine).

```jsonc
"permission": {
  "*": "allow",
  "edit":  { "*": "allow",
              "**/*.sops": "deny", "**/.env.sops": "deny", "**/.env": "deny",
              "secrets/**": "deny", "**/*.age": "deny" },
  "bash":  { "*": "allow",
              "rm -rf /*": "deny",
              "nixos-rebuild switch --target-host *": "deny",
              "docker *up* --target-host*": "deny",
              "ssh *docker compose*up*": "deny",
              "ssh *nixos-rebuild switch*": "deny" }
}
```
Per-repo configs **extend** this with additions scoped to that repo (e.g.
servarr denies `docker volume rm`).

### G2 — Provider policies (litellm + opencode zen + OpenAI Codex CLI direct)

Policies ≠ perms; gate *providers*; survive repo override (global beats
project). Escape hatch: when LiteLLM is offline, fall back to direct
opencode-zen + direct OpenAI Codex CLI subscription.

```jsonc
"provider": {
  "litellm": { /* existing — LiteLLM gateway → kepler/orion inference */ },
  "opencode": {                  // opencode Zen Go (existing flat-rate plan)
    "npm": "@ai-sdk/openai-compatible",
    "name": "OpenCode Zen",
    "options": { "baseURL": "https://opencode.ai/zen/go/v1",
                 "apiKey": "{env:OPENCODE_GO_KEY}" }
  },
  "openai": {                    // NEW — OpenAI Codex CLI subscription direct
    "npm": "@ai-sdk/openai",
    "name": "OpenAI Codex",
    "options": { "apiKey": "{env:OPENAI_API_KEY}" },
    "models": { "gpt-5-codex": { "limit": { "context": 200000, "output": 32000 } } }
  }
},
"experimental": { "policies": [
  { "effect": "deny",  "action": "provider.use", "resource": "*" },
  { "effect": "allow", "action": "provider.use", "resource": "litellm" },
  { "effect": "allow", "action": "provider.use", "resource": "opencode" },
  { "effect": "allow", "action": "provider.use", "resource": "openai" }
] }
```
Replaces the deprecated `disabled_providers` / `enabled_providers` semantics.

### G3 — Theme + attention `tui.json` (tokyonight)

Tokyonight shipped built-in (verified in docs/themes list — `tokyonight`,
`catppuccin`, `catppuccin-macchiato`, `gruvbox`, `kanagawa`, `nord`,
`everforest`, `ayu`, `one-dark`, `matrix`, `system`). Plus attention sounds
on session done/permission/error.

```jsonc
{
  "$schema": "https://opencode.ai/tui.json",
  "theme": "tokyonight",
  "diff_style": "auto",
  "mouse": true,
  "attention": { "enabled": true, "notifications": true,
                 "sound": true, "volume": 0.4,
                 "sound_pack": "opencode.default" },
  "keybinds": { "leader": "ctrl+x" }
}
```
Requires truecolor terminal (`COLORTERM=truecolor`) — Hyprland already
truecolor. Cosmetic only; zero Nix impact.

### G4 — Defer: skills symlink

`~/.agents/skills/` has 40 skills; opencode scans `~/.config/opencode/skills/`
so they are invisible today. Decision D6 deferred per user (2026-06-29); keep
separate until audit. Future: `ln -s ~/.agents/skills ~/.config/opencode/skills`.

---

## PER-REPO scope proposals

Each sister repo gets `opencode.json` at its root, ships in that repo's main.
Extend the global perms, add stack-specific MCPs, scope filesystem to its own
tree + sibling-repo symlinks (where synergies call for it).

### Per-repo: `desktop-nixos` (NixOS fleet source of truth)

```jsonc
{
  "$schema": "https://opencode.ai/config.json",
  "permission": {
    "edit": { "modules/**": "allow", "flake.lock": "ask" },
    "bash": { "just *": "allow",                  // just dry <h>, just lint, just docs-check, just check
              "nix build *": "allow", "nix flake *": "allow" }
  },
  "mcp": {
    "nix":       { "type": "local",
                   "command": ["nix","run","github:utensils/mcp-nixos"],
                   "enabled": true },
    "filesystem":{ "type": "local",
                   "command": ["bun","x","@modelcontextprotocol/server-filesystem",
                   "/home/erik/Documents/erik/desktop-nixos",
                   "/home/erik/Documents/erik/servarr",
                   "/home/erik/Documents/erik/hermes-flake",
                   "/home/erik/Documents/erik/homelab-iac"] }
  }
}
```
- **nix MCP** = `utensils/mcp-nixos` — 2 consolidated tools (search packages +
  search options), explicitly token-light ("we consolidated 17 → 2 because
  your AI's context window isn't infinite"). `nix run` so no install.
- **filesystem MCP** scoped to this repo + 3 sibling symlinks (matches the
  `references/repos/*` coupling map in CLAUDE.md). Skip HA + klipper — small
  value, widen-scope.
- **just** — shell through `bash` (auto-allowlisted); no custom MCP until D3.

### Per-repo: `hermes-flake` (hermes-agent package + NixOS module)

```jsonc
{
  "$schema": "https://opencode.ai/config.json",
  "permission": {
    "bash": { "just build": "allow", "just update": "allow",
              "nix build *": "allow", "nix flake *": "allow" }
  },
  "mcp": {
    "nix": { "type": "local", "command": ["nix","run","github:utensils/mcp-nixos"] }
  }
}
```
Nix-heavy repo. After a version bump → `bump flake.lock` step inside
desktop-nixos syncs the input, so hermes-flake's `just update && just build`
belongs only here.

### Per-repo: `servarr` (multi-host container compose fleet)

```jsonc
{
  "$schema": "https://opencode.ai/config.json",
  "permission": {
    "edit":  { "machines/**/*.{yml,yaml}": "allow",
               "machines/**/.env.sops": "deny", "**/.env": "deny" },
    "bash":  { "*": "ask",
               "just *": "allow", "docker compose *": "ask",
               "docker volume rm *": "deny", "docker rm -f *": "ask" }
  },
  "mcp": {
    "filesystem": { "type": "local", "command": ["bun","x","@modelcontextprotocol/server-filesystem",
                    "/home/erik/Documents/erik/servarr"] }
  }
}
```
- Strict `ask` on raw `docker compose` (must go through `just` recipes per
  CLAUDE.md). `just pull-servarr` / `just kick-stack` auto-allowed.
- Filesystem MCP scoped to this repo only — the gap to `desktop-nixos` is
  closed by that repo's config (which already sees servarr).

### Per-repo: `homelab-iac` (terragrunt + OpenTofu on UniFi)

```jsonc
{
  "$schema": "https://opencode.ai/config.json",
  "permission": {
    "bash": { "terragrunt *": "ask", "tofu *": "ask",
              "just plan-global": "allow", "just apply-global": "ask",
              "just plan *": "allow" }
  },
  "mcp": {
    "tofu": { "type": "local", "command": ["bun","x","opencode-terraform-mcp@latest"] },
    "filesystem": { "type": "local", "command": ["bun","x","@modelcontextprotocol/server-filesystem",
                    "/home/erik/Documents/erik/homelab-iac"] }
  }
}
```
Apply only from a wired LAN host (CLAUDE.md); `apply-global` stays `ask` so
the agent doesn't run network changes wirelessly.

### Per-repo: `home-assistant-config`

```jsonc
{
  "$schema": "https://opencode.ai/config.json",
  "permission": { "bash": { "just *": "allow" } },
  "mcp": {
    "filesystem": { "type": "local", "command": ["bun","x","@modelcontextprotocol/server-filesystem",
                    "/home/erik/Documents/erik/code/home-assistant-config"] }
  }
}
```
HA MCP (REST → make/enable/trigger) exists but the existing skill
(`~/.claude/skills/home-assistant`) covers the same surface; defer adding
until that skill is wired (D-skill).

### Per-repo: `klipper-biqu` (printer config + OrcaSlicer)

```jsonc
{
  "$schema": "https://opencode.ai/config.json",
  "permission": { "bash": { "just orca-sync": "allow" } },
  "mcp": {
    "filesystem": { "type": "local", "command": ["bun","x","@modelcontextprotocol/server-filesystem",
                    "/home/erik/Documents/erik/klipper-biqu"] }
  }
}
```
Minimal — config-only repo.

---

## DEFERRED — containerized `opencode serve` (P6 — exploration per user directive)

Per user 2026-06-29: **defer**. Capture the study here so the future revisit
boots fast. Studied: Hermes container deployment (`modules/hosts/discovery/
hermes-oci.nix`) + reddit `r/opencode` top-year feedback trends.

### Hermes deployment template (proven fleet pattern)
- Lives at `~/Documents/erik/hermes-flake` (sister repo, vendored as flake input)
- `services.hermes-agent-oci` NixOS module wraps `ghcr.io/nousresearch/hermes-agent:latest`
- Container name `hermes-agent`, joins `homelab-net` only → **no published host ports**
- `hostDataDir = /home/$USER/homelab/apps/hermes-agent` bind-mounted RW
- Secrets via sops-nix → `/run/secrets/hermes-agent` → `restartUnits=[docker-hermes-agent.service]`
- SWAG reverse-fronts the vhost: `hermes.homelab.pastelariadev.com → hermes-agent:8642`
- Model egress via internal `http://litellm:4000/v1` (no SSL hop)

A future `opencode-serve` sidecar would mirror this exactly: discovery host,
no published port, SWAG vhost `opencode.homelab…`, model egress via LiteLLM
internal URL, auth via `OPENCODE_SERVER_PASSWORD` from `.env.sops`. Clients
attach via `opencode attach` over SSH.

### Reddit `r/opencode` top-year signal (titles, 2026-06-29)
- "I just switched from claude code to open code" — mainstream migration
- "Visualizing the impact of opencodes plan-before" — plan-before-execute
  is the dominant recommendation; the `gsd-*` commands already ship this
- "goodbye opus hello glm" — GLM routes match our Zen+LiteLLM path
- "in love with deepseek" / "goodbye opencode you're a sink for time and
  tokens" — **lifetime token budgets bite**; supports G2 policies hardening
  + per-repo profiles capping heavy turns
- "can anyone explain how this subscription works" — confirms Zen plan
  confusion; one reason docs push `opencode zen` as the ease-on-ramp
- "well it finally happened to me I got a prompt" — token exhaustion
  interrupts; supports attention sounds (G3) so you catch the wait
- "I made a plugin that gives nonvision models like" / "I created a library
  for opencode that allows you" — plugin ecosystem growing; rtk-style local
  plugins match the trend

Net: nothing reddit-specific changes the design — it reinforces G1+G2+G3.
No widely-recommended community MCP we should adopt that isn't already in the
per-repo proposals.

---

## Decisions to be taken (each blocks a proposal; mark in ADR)

- **D1 Yolo posture — YES** (user 2026-06-29). `permission: "allow"` + denies
  in G1. Wildcards to be test-validated (CLAUDE.md "Bounded iteration"):
  D1-test below.
- **D2 Provider allowlist — YES**: litellm + opencode zen + **OpenAI Codex
  CLI subscription direct** (user 2026-06-29). The Codex key goes in
  `OPENAI_API_KEY` env; models `gpt-5-codex` (verify exact id against OpenAI
  console before relying — Codex CLI subscription just launched).
- **D3 Custom `just` MCP vs shell — DEFER**. Per-repo perms auto-allow `just
  *`, good enough; revisit if the model calls just recipes wrong from raw
  bash. A custom `opencode-just-mcp` adds ~half-day maintenance.
- **D4 Filesystem MCP scope — YES per-repo** (user 2026-06-29). Each repo
  scopes filesystem MCP to itself + sibling symlinks where synergies call
  for it (desktop-nixos = 4 siblings; servarr/hermes-flake/homelab-iac = self
  only).
- **D5 Containerized serve host — DEFER** (user 2026-06-29). When revisited,
  discovery recommended (LAN-close to LiteLLM, same SWAG pattern as hermes).
- **D6 Skills symlink — DEFER** (user 2026-06-29).
- **D7 Phone/termux attach — DEFER** (user 2026-06-29). When revisited, test
  TUI fidelity on small screen with `opencode attach` over SSH; skip
  OpenWebUI front-end until that proves.
- **D8 Auth for serve — DEFER**. When revisited: `OPENCODE_SERVER_PASSWORD`
  from `.env.sops` (servarr-side) — simplest, matches the litellm pattern.
- **D9 Theme — YES tokyonight** (user 2026-06-29). Built-in; verify visually
  before locking.
- **D10 Config home — split user/repo per this proposal** (user 2026-06-29).
  Global `~/.config/opencode/opencode.json` belongs in the user dotfiles
  repo (when you publish one); per-repo `opencode.json` ships in each repo's
  main. No Nix touch.

## User tests needed (acceptance gate per proposal; evidence before "done")

**Global tests** (run once after Phase G):
- **G1**: from flake checkout, prompt `cat secrets/kepler.yaml.sops && rm
  secrets/kepler.yaml.sops` → both deny printed, file untouched. `just dry
  kepler` auto-approves (no prompt).
- **G2**: set `model` inline to `openai/gpt-4o` (not allowlisted) → opencode
  refuses with a policy error. `litellm/qwen-chat`,
  `opencode/kimi-k2-code`, `openai/gpt-5-codex` all route.
- **G3**: open opencode, theme renders tokyonight colors; trigger a 1s task,
  done-sound audible; `afplay` log line or audible.

**Per-repo tests** (one per repo after Phase L):
- **desktop-nixos**: prompt "lookup `services.postfix.enable` option via nix
  MCP, then run `just dry kepler`" → both succeed; context delta < 5K tokens
  (grep `~/.local/share/opencode/log` for `usage`).
- **hermes-flake**: prompt "build the package via just build" → succeeds;
  no MCP token surprise.
- **servarr**: prompt "kick discovery ai-serving" → `just kick-stack
  discovery ai-serving` auto-allowed, runs; raw `docker rm -f litellm` →
  prompts (verify the deny on `docker volume rm`).
- **homelab-iac**: prompt "show me the kepler reservation" — tofu MCP
  resolves state; `apply-global` still prompts.
- **home-assistant-config / klipper-biqu**: filesystem MCP only; verify
  scope can read both repos' trees but cannot edit outside their roots.

## Phasing (smallest-increment first)

- **Phase 0 — audit (this doc, locked)**
- **Phase G — global hardening** (D1 D2 D9 D10): one PR to dotfiles repo
  (when published) carrying `~/.config/opencode/opencode.json` + `tui.json`.
  ~45 min. No remote impact.
- **Phase L1 — desktop-nixos per-repo** (D4 d-nixos): add `opencode.json` at
  repo root, ship in main. Most-used repo. ~30 min.
- **Phase L2 — hermes-flake + servarr per-repo**: ship those `opencode.json`
  files in each repo. ~30 min.
- **Phase L3 — homelab-iac / HA / klipper-biqu per-repo**: ship the
  remaining `opencode.json` files. ~30 min.
- **Phase S — deferred (serve sidecar)**: revisit when D5/D7/D8 unlock.

## Deferred / out of scope

- Migrating gsd-* agents/commands to skills (separate RFC; large touch surface).
- Custom `opencode-just-mcp` npm publish (only if D3 unblocks).
- Desktop opencode IDE extension wiring (different surface; not TUI).
- OpenWebUI front-end on top of `opencode serve` — defer until phone-use
  proves value (D7).
- Auto-commit of long agent sessions → git-history graveyard; needs its own
  policy doc.
- Skills symlink (D6) — defer per user 2026-06-29.
- Containerized `opencode serve` (D5) — defer per user 2026-06-29, study
  preserved above.

---

## Implemented items 2 + 4 (2026-06-30)

Locked post-implementation, retroactive ADR entries:

### Item 2 — durable sops-nix secret source (was D-sops followup)

**Decision:** opencode provider keys go in `secrets/sops/secrets.yaml` and
decrypt to `/run/secrets/opencode/<key>` on every desktop host via a new
NixOS module `laptop-opencode-client` (imported in `profile-desktop.nix`,
same posture as `laptop-hermes-client`).

**Implemented:**
- `secrets/sops/secrets.yaml` += `opencode.litellm_key` +
  `opencode.zen_key` (sops-set by `mint-litellm-keys.sh` consumer rotation,
  values encrypted via the primary+orion+archinaut age key group).
- `modules/hosts/laptop/opencode-client.nix` (new): sops-nix consumer
  mirroring `hermes-agent/client_api_key`. `owner = erik`, mode `0400`,
  `path = /run/secrets/opencode/<key>`.
- `modules/profiles/desktop.nix` += `m.nixos.laptop-opencode-client`
  next to `m.nixos.laptop-hermes-client` (all desktop hosts can run
  opencode; the sops keys decrypt where opencode might run).
- `~/.config/fish/conf.d/zz-opencode-secrets.fish` (user-scope, ships in
  dotfiles later): prefer `/run/secrets/opencode/<key>` over the
  gitignored `~/.config/opencode/secrets.env` fallback.

**Rejected — dotenv file in user dotfiles only:** rejected as the *primary*
path because the secrets live in this flake already (age keys, hermes
pattern proven). A gitignored `secrets.env` remains as fallback for
bootstrapping a fresh host before /run/secrets populates.

**Verification (2026-06-30):**
- `sudo ls /run/secrets/opencode/` lists `litellm_key` (25 B) + `zen_key`
  (67 B), both 0400 owner `erik:users`. Symlinks →
  `/run/secrets.d/41/opencode/<key>`.
- Fresh `fish -c env`: `OPENCODE_LITELLM_KEY` + `OPENCODE_GO_KEY` set from
  the sops path (prefixes match the minted values, not the sops prior state).
- `opencode run --model litellm/qwen-chat` returns pong (qwen-chat
  round-trips through the gateway using the virtual key).

### Item 4 — scoped LiteLLM virtual key in place of master key

**Decision:** replace the LiteLLM master key (full admin) in opencode
consumer config with a per-consumer virtual key (`key_alias = opencode`)
minted via `POST /key/generate`. Allowlist + budget cap.

**Implemented:**
- Minted via curl (`schemas/mint-litellm-keys.sh` is unchanged — out of
  scope to modify that dirty servarr script in this pass):
  - `key_alias = opencode`
  - `max_budget = 20` (USD/day parity cap), `budget_duration = 1d`
  - `models = ["qwen-chat","bge-m3","kimi-k2-code","glm-5",
              "qwen3-max","minimax-m2","mimo","mimo-pro"]`
  - `metadata.consumer = "opencode"`, `purpose = "opencode-cli-coding-agent"`
- Stored in `secrets/sops/secrets.yaml` slot `opencode/litellm_key`.

**Verification (2026-06-30):**
- `GET /v1/models` with the virtual key returns 8 entries (the allowlist);
  rejected models (`whisper-pt-br`, `vision-qwen2vl`) return HTTP 403.
- `POST /v1/chat/completions` with `qwen-chat` and `glm-5` return 200 with
  valid completion. Cloud `kimi-k2-code` round-trips through opencode.ai
  Zen end-to-end on the virtual key.
- LiteLLM Postgres records the key for Langfuse spend attribution via the
  `key_alias=opencode` consumer tag (`POST /key/generate` returns a
  `token_id` joined to `LiteLLM_VerificationTokenTable`).

**Rotation:** re-run `mint-litellm-keys.sh` with a new alias version
(opencode-cli, opencode-cli-stable) or DELETE /key/delete the old alias
record; re-key via `sops set secrets/sops/secrets.yaml '["opencode"]' …`.

### OpenAI Codex subscription + gpt-5.5 (post-bugfix)

Live probe revealed:
- `openai/gpt-5.5`, `openai/gpt-5.4`, `openai/gpt-5.4-mini` — **work
  via existing ChatGPT-account OAuth** (`opencode auth login openai`).
- `openai/gpt-5-codex`, `openai/gpt-5.3-codex-spark`,
  `openai/gpt-5.5-pro` — rejected: "model is not supported when using
  Codex with a ChatGPT account." Require a **real OpenAI API key** (not
  OAuth). The opencode config includes all five anyway, ready for the key
  swap.

**Pending decision:** when you obtain a real OpenAI API key (vs ChatGPT
subscription OAuth), swap by either:
- `opencode auth logout openai` + `opencode auth login openai` reinstalling
  with the new key, or
- set `OPENAI_API_KEY` env var to the real key (overrides OAuth from env
  precedence).

Either unlocks the codex + gpt-5.5-pro routes. Config will be live at
swap time — no edit needed.