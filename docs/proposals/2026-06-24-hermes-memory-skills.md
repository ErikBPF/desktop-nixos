# Hermes Agent — Memory, SOUL & Skills Improvements

**Status:** Partially implemented — **§9 is the authoritative corrected record.**
**Date:** 2026-06-24 (proposal); 2026-06-25 (implementation + corrections)
**Scope:** the live discovery hermes-agent + the flake cutover target.
Touches `servarr` (config), `desktop-nixos` (SOUL canonical + OCI host module),
`hermes-flake` (OCI module / skills wiring).

> ⚠ **Read §9 first.** The implementation (2026-06-25) disproved several core
> premises of §1–§8 against the *running image*. Where §1 (memory framing),
> §4c/§4d/§5 (rtk as a token win), §7 (hook mechanism), or §8 conflict with §9,
> **§9 wins.** Headline: the OCI cutover + skills + SOUL shipped and work; the
> **rtk token-optimization thesis is invalidated on this agent** (rtk never
> fires); the real token levers were never in the original scope; and the deploy
> has a **security posture worth fixing** (redundant `0.0.0.0` publish + YOLO +
> unsandboxed local terminal).

## 0. Context

Live hermes runs the official `nousresearch/hermes-agent` image on discovery,
brain = GLM-5.2 via LiteLLM, aux/compression = MiMo V2.5 (free). Config schema
was synced to upstream v2026.6.19. This doc covers the next layer: **what the
agent remembers, who it is, and what it can do**.

---

## 1. Memory  *(caps bumped — DONE this session)*

Upstream memory = agent-curated notes (`memory_enabled`) + user profile
(`user_profile_enabled`), auto-injected every message.

| key | was (default) | now |
|---|---|---|
| `memory_char_limit` | 2200 (~800 tok) | **10000 (~3.6k tok)** |
| `user_char_limit` | 1375 (~500 tok) | **3000 (~1.1k tok)** |

**Rationale:** 800 tok is starvation for a fleet-wide brain; GLM-5.2 has 200k
ctx. **Cost:** memory is injected *every* turn → ~+3.6k tok/turn billed on the
shared opencode Go budget. Tune down if the $12/5h cap bites.

**Future (not done):**
- **Seed initial memory** with infra facts so the agent doesn't re-learn them.
  Memory files live in `/opt/data/memory/` — could pre-populate, but the
  cleaner split is: *static* facts → SOUL (§2), *learned* facts → memory.
- Revisit `nudge_interval`/`flush_min_turns` once we see real memory churn.

---

## 2. SOUL — rewritten as Erik's personal-agent identity (DONE)

> Implemented 2026-06-24 — see live `modules/hosts/discovery/homelab-SOUL.md`.
> Reframed: Hermes is Erik's **personal** agent (homelab = one active scenario,
> not the only one). Embeds the Karpathy 4 rules, an info-finding hierarchy
> (authoritative source; recipe > doc > memory), the declarative repo→deploy
> method + RFC→ADR→Spec, conventional-commits/ask-before-push, and a
> **nameservers-over-IP:port** preference (e.g. `litellm.homelab…` over
> `litellm:4000`). Plus the **spicyphus doctrine** (`~/Documents/erik/spicyphus`
> MOTIVATION.md): humans seed / LLM refines / machines parse — never originate;
> challenge-before-refine; all decisions wrong until documented; texts-for-
> humans (*why*) vs texts-for-machines (*what/how*); build tapes; opinionated
> over configurable. The earlier draft below is superseded by the file.

### (superseded draft — kept for history)

Current SOUL (`modules/hosts/discovery/homelab-SOUL.md`) is thin and partly
stale: calls the fleet "Docker Compose homelab" (it's NixOS-managed), omits
pathfinder/archinaut, and carries no LiteLLM/deploy facts. Since SOUL is
injected every message and never edited at runtime (verified: seed-if-missing
only), it's the right home for **stable** fleet facts.

Proposed replacement (keep it tight — every line costs tokens/turn):

```markdown
# Hermes — Homelab Agent

You are Hermes, an autonomous agent in Erik's NixOS-managed homelab.

## Fleet (Tailscale mesh; IPs are DHCP-reserved on the UDM)
- **discovery** (.210) — 24/7 infra: media, monitoring, LiteLLM gateway,
  Langfuse, and you. Always on.
- **kepler** (.230) — NAS, AI serving (GPU), k3s, CI.
- **orion** (.220) — AI inference (llama.cpp); SLEEPS for gaming, so anything
  routed to it (qwen-chat) can be offline at night.
- **pathfinder** (.125) — workstation.
- **archinaut** (.225) — RPi3 running the BIQU B1 Klipper printer.
- **laptop** — roaming (Tailscale only).

## Model access — ALWAYS via LiteLLM, never direct
One gateway: `http://litellm:4000/v1` (ext: litellm.homelab.pastelariadev.com).
Your brain is GLM-5.2 (`glm-5`); compression/aux is MiMo V2.5. Switch models
with `/model <glm|kimi|qwen|qwen-max|minimax|mimo|mimo-pro>`. Every model call
is traced in Langfuse and shares a flat opencode-Go budget — prefer the local
`qwen` for cheap bulk work when Orion is awake.

## How this homelab changes
Config flows **repo → deploy**, never hand-edited on a host. System config is
NixOS (`desktop-nixos`, `just switch-<host>` / `just deploy`); container stacks
are `servarr` (`just sync-servarr <host>`). Never edit files on a host over SSH.

## Behavior
Concise, technical, practical. Accuracy over verbosity. When acting on the
homelab, name the `just` recipe rather than open-coding remote commands.
```

**Resolved:** HA = `192.168.10.115` (stale `.205` in `CLAUDE.md` fixed). Fleet
table includes archinaut; Voyager dropped (not a fleet host). Routing detail in
SOUL kept minimal (gateway + DNS rule); per-model specifics stay in config.

---

## 3. Skills — architecture

Today skills are agent-created in `/opt/data/skills` (mutable, restic-backed,
but not git-versioned, not shared with the laptop CLI). Upstream supports
`skills.external_dirs`: **read-only external skill dirs**, shared across
agents, `~`/`${VAR}`-expanded, local skills win on name collision.

**Proposal — version-control skills like everything else:**
1. A git-managed `skills/` tree (home: see decision below), mounted read-only
   into the container, wired via `skills.external_dirs`.
2. Wins: declarative + reviewable (not an opaque restic blob), **portable**
   (discovery gateway + laptop `hermes` CLI share one set), survives state
   wipes.
3. Folds into the OCI cutover: the module adds a read-only volume + sets
   `external_dirs` — same shape as the SOUL single-source.

**Decision for Erik:** skills repo home — `desktop-nixos`
(`modules/hosts/discovery/hermes-skills/`) vs a dedicated `hermes-skills`
repo (better for laptop+gateway sharing). And: wire onto the live Docker now,
or ride the OCI cutover.

---

## 4. Proposed skill catalog

**Skill format** (upstream `developer-guide/creating-skills.md`): a folder with
a required `SKILL.md` (YAML frontmatter: `name`, `description`, `version`,
`author`, `license`, optional `platforms`, `metadata.hermes.tags` /
`related_skills` / `requires_toolsets`) + optional `scripts/` and `references/`.
Rule of thumb: **Skill** = instructions + shell/CLI + existing tools (no code in
the agent); **Tool** = needs API keys/auth/custom Python baked in. Most of the
below are Skills.

**Already built this session:** `reddit-research` — a no-OAuth Reddit scraper
(arctic-shift backend; the `.json` trick is dead). Lives at
`~/Documents/erik/hermes-skills/research/reddit-research/` (SKILL.md +
`scripts/reddit_scrape.py`). First concrete skill + the tool that unblocked §4e.

### 4a. `disciplined-engineering` — Karpathy's 4 principles
Source: [multica-ai/andrej-karpathy-skills](https://github.com/multica-ai/andrej-karpathy-skills).
The four: **Think Before Coding** (state assumptions, surface alternatives),
**Simplicity First** (minimal code, no speculation), **Surgical Changes**
(touch only what's needed), **Goal-Driven Execution** (verifiable criteria,
loop until met). Adapt their `skills/karpathy-guidelines/` into a hermes skill
so the agent applies them on any code task. Already Erik's global Claude Code
convention (`~/.claude/KARPATHY.md`) — this brings parity to hermes.

### 4b. `wiki-curator` — Karpathy's "LLM Wiki" pattern
Source: [Karpathy gist](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f)
(*LLM Wiki: A Pattern for Personal Knowledge Bases*, 2026-04). Not a fact file —
a **pattern**: a 3-layer git-tracked markdown knowledge base — (1) raw sources
(immutable), (2) an LLM-maintained wiki (summaries, entity pages,
`[[wikilinks]]`, `index.md` + `log.md`), (3) a schema doc guiding upkeep. Ops:
**ingest / query / lint**. The wiki is a *compounding* artifact, not ephemeral
chat.

This is bigger than a skill — it's the **right shape for hermes memory**. Two
moves: (a) a `wiki-curator` skill that ingests/queries/lints a git-tracked wiki
under the skills/`external_dirs` tree; (b) it directly informs §1 memory + the
Reddit "Dreaming" idea (§4e) — nightly consolidation writing into a structured,
linkable wiki instead of flat memory files. Strongly recommended as the
backbone of the memory story.

### 4c + 4d. `rtk` + `caveman` — ADOPT, don't build
Both already have working **Hermes** implementations — no need to port from
scratch:
- [`adityahimaone/hermes-agent-rtk-caveman`](https://github.com/adityahimaone/hermes-agent-rtk-caveman)
  — combined RTK + caveman + **35+ pre-configured skills**, claimed 90–99% token
  savings on CLI ops (shortcuts like `cgs`/`cgl`/`clint`/`ctest`).
- [`poyhsiao/hermes-rtkit`](https://github.com/poyhsiao/hermes-rtkit) and
  `ogallotti/rtk-hermes` — RTK plugins that intercept via `pre_tool_call`,
  auto-load on gateway boot, zero config.
- Official installer: `rtk init --agent hermes`.
- [`0xNyk/awesome-hermes-agent`](https://github.com/0xNyk/awesome-hermes-agent)
  — curated skills/tools/integrations to mine further.

RTK = input-side (compress tool output 60–90%); caveman = output-side (terser
responses ~65%). Together they cut the shared Go budget at both ends. Both are
Erik's existing Claude Code setup (`~/.claude/RTK.md`, caveman mode) — bring
parity to hermes. **One real eng bit:** `rtk` must exist in the container —
needs an image layer or wrapper (the official image won't have it). Resolve in
the OCI module. **Action:** vet `adityahimaone`'s repo, adopt the plugin +
cherry-pick from its 35 skills rather than reinventing.

### 4e. Reddit post — `u/HolmeBengt`'s 28-cron / 30-skill setup
Retrieved via the new `reddit-research` skill. His skills, with homelab fit:
- 🌙 **Dreaming** *(adopt)* — nightly 3 AM: read all conversations, extract
  decisions/projects/bugs/mistakes → structured summary auto-loaded at session
  start. Directly addresses our §1 memory gap; pairs with §4b wiki-curator.
- 💬 **Feedback Loop** *(adopt)* — every correction saved; weekly pattern
  analysis → updates its own system prompt. Self-improving SOUL/persona.
- 🖥️ **Infra Monitoring** *(homelab-native)* — periodic host/site/security
  checks + alerts. We already have Grafana/Prometheus/healthchecks/HA — a skill
  that *queries* those and reasons over them, not a reinvent.
- 📋 **Daily Status Report** *(homelab-native)* — morning briefing: calendar,
  todos, system health, overnight anomalies. Tactical dashboard via Telegram.
- 🧠 **Wisdom Vault** *(optional)* — capture insights → Notion → Anki spaced
  repetition.
- 🥗 Health Coach, 📚 Study Audit, 💰 Finance Review, 📬 Mail Gatekeeper —
  personal-life automations; inspiration, lower priority for the homelab.

His meta-lessons (worth heeding): **one file / one job / no deps per skill**;
self-built beats downloaded (fits your workflow, you can fix it); and his honest
caveat — long-term memory is still the hard part, a generic Obsidian
integration "sits unused." → invest in the *Dreaming + wiki* memory loop, not a
passive note store.

---

## 5. Rollout

1. **Done:** memory caps live; `reddit-research` skill built.
2. SOUL rewrite (§2) → update canonical `homelab-SOUL.md` (auto-mirrors to
   servarr via the wired `sync-servarr` step).
3. **Skills repo + wiring:** decide home (recommend a dedicated `hermes-skills`
   repo — already seeded locally — so the laptop CLI + discovery gateway share
   one set), scaffold the `external_dirs` mount on the live Docker (volume +
   `skills.external_dirs`), no need to wait for the OCI cutover.
4. **Adopt rtk + caveman** (§4c/4d) from `adityahimaone`'s repo — fastest token
   win at both ends. The only build work: get `rtk` into the container (image
   layer / wrapper) — fold into the OCI module.
5. **Memory backbone:** stand up `wiki-curator` (§4b) + a `Dreaming` nightly
   consolidation cron (§4e). This is the high-effort/high-value track — the
   Reddit author's #1 unsolved problem, and where the LLM-wiki pattern pays off.
6. Then `disciplined-engineering` (§4a) + the homelab-native `infra-monitor` /
   `daily-status` skills that query the existing Grafana/HA stack.

---

## 6. Ecosystem picks — `0xNyk/awesome-hermes-agent`

> **Security caveat (read first):** these are community repos. Adopting one =
> running third-party code inside a hermes container that has `HERMES_YOLO_MODE`
> + terminal access on the homelab network. **Vet the source before install**,
> prefer local/no-egress options, pin a commit, and don't blanket-trust the
> "90-99% savings / N skills" claims. Treat like any supply-chain dependency.

Curated against the homelab bias (local-first, git-tracked, no cloud egress).

### Memory (+ Obsidian)
- **[Mnemosyne](https://github.com/AxDSan/Mnemosyne)** — SQLite + sqlite-vec
  hybrid search + **temporal knowledge graph**. Local, structured, graph-shaped
  — best fit for the §4b wiki backbone. *Top pick.*
- **[ClawMem](https://github.com/yoloshii/ClawMem)** — on-device memory, **no
  external APIs**. Aligns with the no-cloud-egress invariant.
- **[autocontext](https://github.com/greyhaven-ai/autocontext)** — recursive
  context curation/compression (complements hermes' own compression).
- **Obsidian:** [Hermes Console](https://github.com/dannyshmueli/obsidian-hermes-console)
  exists, BUT the Reddit author's warning stands (generic Obsidian "sits
  unused"). Better: the §4b `wiki-curator` *emits* Obsidian-compatible markdown
  (`[[wikilinks]]`, git-tracked) — you get an Obsidian-viewable vault without a
  heavy plugin. Skip the integration; produce the vault.

### Architecture planning
- **[oh-my-hermes](https://github.com/witt3rd/oh-my-hermes)** — `ralplan`
  (consensus planning) + `ralph` (verified execution). Maps onto your
  RFC→ADR→Spec flow + Karpathy goal-driven execution; complements BMAD. *Top
  pick.*
- Honorable: [execplan-skill](https://github.com/tiann/execplan-skill)
  (long-running task lifecycle), [PolyBrain](https://github.com/mosesman831/PolyBrain)
  (objective → JSON task plan).

### TDD / testing
- **[hermes-eval](https://github.com/Saurav0989/hermes-eval)** — skill
  regression testing + trajectory scoring. **Essential once the skill library
  grows** (the Reddit author's pain: "30 skills = 30 things that break"). *Top
  pick.*
- **[lintlang](https://github.com/roli-lpci/lintlang)** — static linter for
  agent configs/prompts (validate `SKILL.md` + persona).
- For code TDD: a `tdd` workflow skill (write failing test → pass → refactor),
  matching Karpathy "transform tasks into verifiable goals."

### Code development
- **[abvx-agent-skills](https://github.com/markoblogo/abvx-agent-skills)** —
  "smaller diffs, evidence-led debugging, token control." Literal Karpathy
  surgical-changes + budget discipline. *Top pick.*
- **[hermes-skill-factory](https://github.com/Romanescu11/hermes-skill-factory)**
  — auto-generate skills from workflows (accelerates building the rest).
- [tech-debt-management-skill](https://github.com/Vincent-crypto-coder/tech-debt-management-skill)
  — pylint/radon/bandit scan → prioritized refactor plan.

### Information organization / indexing
- **[sourcevault-code-tools](https://github.com/Ocasio-Perez/sourcevault-code-tools)**
  — private **local** semantic code search. Index the homelab repos
  (desktop-nixos / servarr / hermes-flake) so the agent can navigate them.
  *Top pick.*
- [hermes-drive-index](https://github.com/gregoryhorn/hermes-drive-index) —
  private local full-text index. [HermesWiki](https://github.com/martymcenroe/HermesWiki)
  — community pattern wiki (reference, not a dep).

### Synthesis
The local-first stack that hangs together: **Mnemosyne** (memory/graph) +
`wiki-curator` (Obsidian-compatible vault) + **Dreaming** cron for the memory
loop; **oh-my-hermes** for planning; **hermes-eval** + **abvx** for build
quality; **sourcevault** to index the repos. All local/git — no new cloud
egress. Adopt incrementally, vetting each.
```

---

## 7. Review & implementation log — 2026-06-25

Grilled the proposal against the **running image** (`nousresearch/hermes-agent`
v2026.6.19 on discovery) instead of trusting docs/community claims. Did Phases
**0, 1, 3** (Phase 2 memory backbone deferred). Verification = evidence from
`docker exec`, not assertion. Corrections below override the prose above where
they conflict.

### Phase 0 — verify & measure  *(DONE)*

- **`skills.external_dirs` is REAL** — `agent/skill_utils.py::get_external_skills_dirs`.
  Confirmed semantics: `~`/`${VAR}` expansion, relative paths resolve against
  `HERMES_HOME` (`/opt/data`), **existing dirs only** (missing → silently
  skipped), recursive `SKILL.md` scan, **local `/opt/data/skills` wins on name
  collision**, read-only (new skills only ever created in the local dir). This
  was the load-bearing unknown — §3 is sound.
- **SOUL mutability contradiction RESOLVED.** §2's "never edited at runtime" is
  *false in the abstract* — `hermes_cli/web_server.py` exposes a SOUL.md write
  endpoint, so the app **can** self-edit it. **But** the live deploy bind-mounts
  `SOUL.md:ro` (owner uid 1000, not the container's 10000), so it is immutable
  *in practice* and the single-source sync holds. **Decision (locked): SOUL
  stays `:ro`/declarative.** Any future self-improvement (§4d Feedback Loop)
  must write a *separate* `learned-*.md`, never SOUL. This kills the §4d
  "updates its own system prompt" design as written — re-scope it.
- **Baseline (static per-turn injection):** SOUL 4276 chars + memory 10000 +
  user-profile 3000 + a ~55 KB skills snapshot (compacted in-prompt; 28 bundled
  skill categories already shipped in the image). The dynamic Phase-3 metric
  (tool-output tokens, what rtk would compress) lives in Langfuse traces — that
  is the live gate, not a static number.

### Phase 1 — skills wiring  *(DONE + verified)*

Wired the git-versioned `hermes-skills` repo into the **live Docker** (no OCI
cutover needed), as §3/§5.3 recommended:

- `servarr` compose: read-only mount `/home/erik/hermes-skills:/opt/skills-ext:ro`.
- live `config.yaml`: `skills.external_dirs: ["/opt/skills-ext"]`.
- `desktop-nixos` justfile: new `just sync-hermes-skills <host>` (rsync, mirrors
  the `sync-servarr` shape; `references/repos/hermes-skills` symlink added).
- **Verified end-to-end:** mount present + `ro`; container healthy;
  `get_external_skills_dirs()` → `['/opt/skills-ext']`; forced index rescan
  renders **caveman, reddit-research, skill-forge** in the skills system prompt.

### Phase 3 — token discipline  *(caveman DONE; rtk mechanism corrected, BLOCKED on one decision)*

- **caveman (output-side) — DONE.** Built `meta/caveman/SKILL.md` in
  `hermes-skills` (output compression as a writing posture; auto-clarity carve-
  outs for security/irreversible/ordered steps). It is *correctly* a
  skill/prompt directive, **not** a hook: a `transform_llm_output` hook would
  post-process *after* generation and save zero generation tokens — only a
  prompt directive makes the model write terser. Live + in the index.

- **rtk — the proposal's mechanism (§4c/§4d) is DISPROVEN; do not adopt
  community repos blind.** Evidence from the running image:
  - `pre_tool_call` hooks **can only block or pass through** — `_parse_response`
    ignores any rewrite payload (`agent/shell_hooks.py`). So "rtk intercepts via
    `pre_tool_call`" (the `adityahimaone`/`poyhsiao` claim) **cannot rewrite a
    command** in this image. Shell hooks are block-only.
  - The hook surface *does* expose `transform_terminal_output` /
    `transform_tool_result` / `transform_llm_output` — but only **Python
    plugins** (loadable from `/opt/data/plugins/`, no image rebuild) can use
    them; shell hooks can't transform.
  - **rtk has no stdin→stdout filter mode** — it is a *command proxy*
    (`rtk git status`, `rtk ls`, `rtk grep …`), so a transform-hook plugin would
    have to re-parse and re-execute commands (fragile, double-exec, dangerous).
    Rejected.
  - **The only sound integration is instruction-based** (what `rtk init` does):
    rtk binary on the container PATH + a skill telling the agent to call
    `rtk <cmd>` for supported ops. The agent opts in; no hook, no custom Python.
  - **Feasibility proven:** the workstation rtk 0.35.0 is a **static-pie x86-64**
    binary (no glibc dep); copied into the container it runs (`rtk --version`,
    `rtk git --help` OK). Container is x86-64 Debian 13.
  - **Decision (Erik, 2026-06-25): bake rtk into the `hermes-flake` OCI image**
    — most declarative; rtk arrives with the OCI cutover (the module is
    currently disabled; live path is still the servarr Docker compose). The two
    quicker paths (sync-binary-and-mount; nix `systemPackages`) were rejected in
    favour of declarative purity. **Implication: rtk does NOT go live this
    session** — it becomes a `hermes-flake` cutover task.
  - **Concrete bake recipe** (for the cutover): the OCI module pulls the
    *official* image as-is (no layering today), so add a derived image —
    `dockerTools.buildImage { fromImage = <pinned official>; copyToRoot = [ rtk ]; }`
    (or `streamLayeredImage`) — and point `services.hermes-agent-oci.image` at
    it. That needs rtk **packaged for Nix** first (`fetchurl` the static release
    binary, or `rustPlatform.buildRustPackage` from source) — the static-pie
    x86-64 binary verified this session drops straight into the image, no glibc
    concern. Then ship the `rtk` skill (instruction-based usage) in the same
    change, since the binary is finally present.
  - The rtk **skill is intentionally NOT shipped yet** — instructing the agent
    to use `rtk` while the binary is absent would trip `tool_loop_guardrails`.
    Skill lands with the OCI-image bake, not before.

### Not done / deferred

- **Phase 2 memory backbone** (`wiki-curator` + Dreaming cron) — untouched.
  Note for when it starts: hermes has a real `cron/scheduler.py` and hook events
  `on_session_start/end/finalize/reset`, so "Dreaming" can be a native cron job,
  not an external systemd timer. Bound the "read all conversations" cost.
- **§1 memory caps** — left at 10000/3000. Recommendation stands: these were
  raised *before* curation exists, so re-evaluate against Langfuse once Phase 2
  lands; lower if the auto-notes are low-signal.
- **§6 community repos** — none adopted. The §6 security caveat now explicitly
  extends to §4c/§4d (rtk/caveman community repos), whose mechanism we disproved.

### Files touched this session

- `servarr/machines/discovery/config/hermes-agent/config.yaml` (+`external_dirs`)
- `servarr/machines/discovery/hermes-agent.yml` (+skills-ext `:ro` mount)
- `desktop-nixos/justfile` (+`sync-hermes-skills`)
- `hermes-skills/meta/caveman/SKILL.md` (new)
- `desktop-nixos/references/repos/hermes-skills` (symlink; gitignored)

---

## 8. OCI cutover — build + dry-eval — 2026-06-25

Decision (Erik): migrate the live discovery hermes off the servarr Docker
compose onto the **hermes-flake OCI NixOS module** (official image + Nix-rendered
config/SOUL/sops, declarative). rtk delivery = **store-mount** (not a dockerTools
image bake — the vendor image is multi-GB; a 3 MB static binary mounted RO from
the nix store is equally declarative, keeps pull-to-upgrade, no digest churn).
Scope this session = **build + dry-eval only; no live switch.**

### Built (in-repo, reversible — nothing deployed/pushed)

- **`hermes-flake/nixos/oci.nix`** — two generic options added: `networks`
  (→ `--network=<n>`, no auto-dependency, verified safe for the externally-
  managed `homelab-net`) and `extraVolumes` (appended to the config/SOUL/data
  mount set). `extraEnvironment`/`telegramAllowedUsers` already flowed through.
- **`desktop-nixos/modules/hosts/discovery/hermes-oci.nix`** (new,
  `flake.modules.nixos.discovery-hermes-oci`):
  - `services.hermes-agent-oci` — backend docker, container name `hermes-agent`,
    ports 8642/8644, `openBindAddress 0.0.0.0`, `memoryMax 2g`.
  - `hostDataDir = /home/erik/homelab/apps/hermes-agent` — **reuses the existing
    live state subvol** (memories/sessions/skills/venv survive the swap).
  - `networks = ["homelab-net"]` — mandatory: reach `litellm` by name + be
    reached by SWAG by name.
  - `extraVolumes` = rtk store-mount (`${rtk}/bin/rtk:/usr/local/bin/rtk:ro`) +
    git skills (`/home/erik/hermes-skills:/opt/skills-ext:ro`).
  - rtk packaged inline as a FOD (`fetchurl` the v0.42.4 musl static tarball,
    `sha256-NJdRFtoR4J5QJQHa91gUPgsi7TpCoQ62f7aTpicNnjY=`).
  - `settings` migrated **verbatim from the live config.yaml** (glm-5 brain,
    MiMo/qwen aux, memory caps 10000/3000, `skills.external_dirs`, 7
    model_aliases); the rest inherits `config.yaml.nix` defaults.
  - `soulFile = ./homelab-SOUL.md`; sops `hermes_agent/server_env` →
    `/run/secrets/hermes-agent`, `restartUnits = docker-hermes-agent.service`.
- **`discovery/default.nix`** — import swapped: disabled nspawn blueprint →
  `discovery-hermes-oci`. (The old `./hermes-agent.nix` nspawn module is
  superseded — left in place, no longer imported.)

### Verified (dry — `nixos-rebuild dry-build`, local hermes-flake override)

- Eval clean; plan realizes `docker-hermes-agent.service` + `hermes-config.yaml`
  + `rtk-0.42.4`. No errors.
- Container attrs: `networks=["homelab-net"]`; volumes include **both** rtk and
  skills-ext mounts; env has `OPENAI_BASE_URL=http://litellm:4000/v1`,
  `TELEGRAM_ALLOWED_USERS`, `DISCORD_ALLOWED_USERS`, `API_SERVER_HOST=0.0.0.0`.
- Rendered config.yaml matches live: `default: glm-5`, aux `mimo`/`qwen-chat`,
  `memory_char_limit 10000` / `user_char_limit 3000`, `external_dirs:
  [/opt/skills-ext]`, all 7 aliases.

> Safe to leave uncommitted: discovery `autoUpgrade` pulls from **remote**
> `github:ErikBPF/desktop-nixos#discovery`, so unpushed local changes never
> auto-deploy. The cutover is a deliberate manual step.

### Cutover runbook (NOT done — separate go required)

**Pre-flight (do first, all reversible):**
1. **sops env — add bare names.** Edit `secrets/sops/secrets.yaml`
   `hermes_agent/server_env`: add `TELEGRAM_BOT_TOKEN` and `DISCORD_BOT_TOKEN`
   (copy values from the `HERMES_`-prefixed entries). **Verify `OPENAI_API_KEY`
   == the LiteLLM key** (config uses `${OPENAI_API_KEY}` against the litellm
   base_url) — set it equal to `LITELLM_API_KEY` if not. Re-encrypt.
2. Confirm `/home/erik/hermes-skills` is synced on discovery
   (`just sync-hermes-skills discovery`) — the `:ro` mount must exist or the
   external_dirs entry is silently skipped.
3. `just dry discovery` once more from a clean tree after committing.

**Switch (brief gateway downtime):**
4. Stop + remove the compose hermes so it frees the name/ports and won't restart:
   `cd ~/servarr/machines/discovery && docker compose -f hermes-agent.yml --env-file .env down`.
   Remove `hermes-agent` from any servarr up-all list so it can't be re-upped
   (leaf-repo change in `servarr`).
5. Commit desktop-nixos + the hermes-flake `oci.nix` change; bump
   `flake.lock` (`nix flake lock --update-input hermes-flake`) so the remote
   build sees the new module options.
6. `just switch-discovery`.

**Verify (evidence, not assertion):**
7. `systemctl status docker-hermes-agent.service`; container `healthy`;
   `docker inspect hermes-agent` shows `homelab-net` + the rtk/skills mounts.
8. In-container: `rtk --version`; `get_external_skills_dirs()` →
   `['/opt/skills-ext']`; litellm reachable (`curl http://litellm:4000/v1/models`
   from the container); `/opt/data` still holds prior memories/sessions.
9. SWAG: `curl -sf https://hermes.homelab.…/health`. Telegram + Discord round-trip.
10. Ship the **rtk skill** to `hermes-skills` (now that the binary is on PATH)
    + `just sync-hermes-skills discovery`; recreate to pick it up.

**Rollback:** revert the `default.nix` import + `git checkout` lock, re-up the
compose stack (`docker compose -f hermes-agent.yml --env-file .env up -d`),
`just switch-discovery`. State dir is shared, so no data move either way.

### Open cutover risks

- **homelab-net boot ordering** — `docker-hermes-agent.service` needs the
  external `homelab-net` to exist first. Same dependency the live compose has;
  systemd will restart until the network is up. Watch first reboot.
- **`:latest` image** — OCI doesn't auto-repull `:latest`; pin a digest when
  convenient (the module notes this). Not a blocker for the swap.
- **`config.yaml` drift** — the OCI path mounts the Nix-rendered config `:ro`
  (same as compose), so the live `/opt/data/config.yaml` `.bak-*` churn stops;
  any runtime-written config state is shadowed. Expected.

---

## 9. Post-implementation verdict & implementation grill — 2026-06-25 (authoritative)

Everything below is validated against the **running container** (live `docker
exec`, real chat-completion turns, request-dump measurement). It supersedes the
rtk / cost / hook claims in §1, §4c–§4d, §5, §7, §8 wherever they conflict.

### 9.1 What actually shipped and works
- **OCI cutover (§8): DONE, live, durable.** discovery hermes runs the
  hermes-flake OCI module (official image + Nix-rendered config/SOUL/sops,
  `homelab-net`, reused state dir). Telegram/Discord/SWAG/litellm all verified.
  Pushed → survives autoUpgrade.
- **skills `external_dirs` (§3): works.** caveman/rtk/reddit/skill-forge render
  in the index; the git `hermes-skills` repo is the source, synced via
  `just sync-hermes-skills`.
- **SOUL `:ro`/declarative (§7): correct.**
- **YOLO auto-approve: works** (`HERMES_YOLO_MODE=1` + `approvals.mode=off`) —
  but see 9.4, it interacts badly with the network exposure.

### 9.2 The rtk thesis is INVALIDATED on this agent  *(corrects §1/§4c/§5/§7/§8)*
rtk **never fires** in normal operation. Chain of evidence:
- rtk is a *command proxy* — it only helps when it is the thing running the
  command (`rtk git status`).
- The rtk-rewrite **plugin works mechanically** — `pre_tool_call` *can* rewrite
  by mutating `args["command"]` in place (a Python plugin gets the live dict by
  reference via `get_pre_tool_call_block_message` → `invoke_hook(args=args)`).
  **This corrects §7's wrong claim that `pre_tool_call` can only block** — that
  is true for *shell* hooks, not Python plugins.
- BUT the hook only fires for the **`terminal` tool**, which lives in the
  **coding toolset**, exposed only in coding posture (`agent.coding_context=
  focus` or cwd=git-repo). The default gateway posture (Telegram/Discord/API
  chat) exposes only **`execute_code`** (python sandbox) which runs shell via
  raw `subprocess` → bypasses the tool layer entirely.
- Measured: `rtk-rewrite` logged **0 rewrites**; `rtk gain` empty after multiple
  real turns.
- The instruction-based nudge (rtk skill + SOUL line) **was ignored** by the
  model — adoption-by-prompt does not work here.
- Only reliable way to force rtk: `agent.disabled_toolsets=["code_execution"]`
  (loses the python sandbox) — **declined.**

→ **rtk is installed but idle.** §5.4's "fastest token win at both ends" is
false for this deployment. The rtk plugin/skill/mount are dead weight kept by
choice; they can be ripped out with no functional loss.

### 9.3 The real token levers — never in the original scope  *(corrects §1/§5)*
Measured from a real request dump (`request.body.{messages,tools}`):
- **tools array ≈ 13k tok/turn** (27 defs; `delegate_task` + `cronjob` ~1.9k
  *each*, `browser_*` ~1.7k) — every turn, every session.
- **SOUL ≈ 4k**, **memory/profile ≈ up to 3k** (caps 10000/3000, kept by choice).
- **Coding sessions add ≈ 14k**: coding posture injects the cwd's `CLAUDE.md`
  files (global + repo) verbatim as a `developer` message.
- rtk targets *tool output*, the **smallest** lever. The actual reductions are:
  `agent.disabled_toolsets` (drop delegation/cron/browser/vision → ~6k/turn) and
  trimming CLAUDE.md injection — **neither appears in §1–§6.** Lever identified,
  not applied (user kept current state).
- **The cited cost gate doesn't exist:** §7 says "watch Langfuse." The Langfuse
  plugin is **off** (`plugins.enabled` lacks it, 0 log mentions) — hermes is not
  tracing there. Measure via request dumps (error-only) or enable the plugin.

### 9.4 Implementation grill — security & hygiene
1. **Redundant `0.0.0.0` port publish.** Container publishes `0.0.0.0:8642/8644`
   on the host, but SWAG reaches it over `homelab-net` DNS (`hermes-agent:8642`).
   The host publish is **unnecessary LAN attack surface**. Combined with
   `terminal.backend: local` (unsandboxed) + YOLO + `approvals.mode=off`, the
   API on the LAN = autonomous dangerous-command execution surface — the exact
   trifecta the api_server log warns about. **Fix:** drop the host port publish
   (bind loopback or omit `ports`; SWAG still works over homelab-net); consider
   `terminal.backend: docker`. The hardcoded catastrophic floor is the only
   remaining guard.
2. **`networking.firewall.allowedTCPPorts = lib.mkDefault []` is a no-op.** Docker
   publishes via its own iptables chain, bypassing the nixos firewall; the line
   + comment imply control that doesn't exist. Remove.
3. **Dead sops keys** post-cutover: `LITELLM_API_KEY`, `OPENROUTER_API_KEY`,
   `HERMES_TELEGRAM_BOT_TOKEN`, `HERMES_DISCORD_BOT_TOKEN` (OCI uses the bare
   names + `OPENAI_API_KEY`). Prune.
4. **`enableHealthcheck` is a silent no-op on the OCI path** — `nixos/oci.nix`
   never imports `healthcheck.nix`. The option lies. → hermes-flake bug.
5. **homelab-net boot ordering** — no unit dependency on the external network;
   crash-loops at boot until the servarr networking stack creates it.
6. **caveman "DONE" = installed, not used.** Same adoption gap as rtk — never
   validated as actually changing output. Treat as unproven, not a win.

### 9.5 Corrected recommendation
- **Keep:** OCI cutover, skills `external_dirs`, SOUL, caveman (harmless), **rtk
  (idle, kept by decision 2026-06-25)**.
- **Fix (security) — APPLIED 2026-06-25** (commit `1fa8c03`): `publishPorts=false`
  (new hermes-flake oci option) drops the host `0.0.0.0:8642/8644` mapping —
  verified host port gone + SWAG still 200 over homelab-net; no-op firewall line
  removed; dead sops keys pruned (now 5: OPENAI/API_SERVER/EXA + bare
  TELEGRAM/DISCORD). **Still open:** `terminal.backend: docker` (sandbox) given
  YOLO — deferred, not applied.
- **Real token work (if pursued):** `agent.disabled_toolsets` for unused
  toolsets; trim/scope the CLAUDE.md injection in coding posture. Measure via
  request dumps, not Langfuse (off).
