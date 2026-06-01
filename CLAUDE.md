## Commit policy

Never add `Co-Authored-By: Claude …` (or any other Anthropic attribution) to
commit messages or PR bodies in this repo. Commits should read as if a human
authored them; the only signature is the configured `git user.name` /
`user.email`.

The universal **Defensive Commit Rules** from `~/.claude/CLAUDE.md` apply
here. The items below extend (not relax) them with repo-specific patterns.

## Repo-specific never-commit patterns

- **Nix build artifacts**: `result`, `result-*` symlinks, `.direnv/`, anything
  under `/nix/store` paths. These are reproducible — they belong on disk, not
  in git.
- **Secrets are sops-encrypted only**: `*.yaml`/`*.json` files containing
  unencrypted credentials must never land in this repo. Verify
  `secrets/*.yaml` is sops-encrypted (`sops: …` block present) before staging.
- **VM / disk images**: `*.qcow2`, `*.img`, `*.iso`, `*.vmdk`. Use a fixture
  fetcher in `flake.nix` instead.
- **Hardware-specific generated config**: `hardware-configuration.nix` is per
  host — confirm before committing changes that came from
  `nixos-generate-config` on another machine.
- **Compiled BMAD assets**: anything under `_bmad/.cache/` or runtime state
  produced by `/bmalph-*` commands.

## Remote actions — autonomous, but channelled

Claude **may** update remote hosts (`pathfinder`, `kepler`, `discovery`,
`orion`, `laptop`, hermes targets, servarr targets) without prompting per
command, **on the strict condition** that every remote-touching action goes
through a documented entry point:

- `just` recipes in `desktop-nixos/justfile` (`just deploy …`,
  `just switch-<host>`, `just sync-servarr <host>`, `just sync-stack <host>
  <stack>`, etc.)
- `just` recipes in sister repos (`servarr/justfile`,
  `hermes-flake/Justfile`).
- Deploy docs in `docs/` and `references/` — follow them verbatim. If a doc
  and a recipe disagree, the recipe wins (the doc is stale; flag it).

Forbidden even with the above autonomy:

- Raw `nixos-rebuild switch --target-host …` invocations that bypass
  `just deploy`. The recipe carries the substitutes/sudo/port flags — open
  coding it loses those guarantees.
- Editing files **on** a remote host over SSH instead of changing the source
  repo and re-deploying. Configuration must always flow `repo → deploy`.
- Anything destructive on the remote (`rm`, `docker volume rm`,
  `zpool destroy`, `nixos-rebuild --rollback` past a known-good generation,
  partition / LUKS / sops key operations) — those still require explicit
  user confirmation in the turn.
- Touching unmerged in-progress state on a remote host (`/srv/work`,
  databases mid-migration). If unsure whether state is live, ask.

Verification expectations:

- Before `switch`, run `just dry <host>` (or repo equivalent) and skim the
  diff for surprises.
- After `switch`, verify with `systemctl status` / `journalctl -u` / curl on
  the affected service. A green `nixos-rebuild` is not proof the service
  came up.

## Cross-repo synergies

This flake (`desktop-nixos`) is the source of truth for host system
configuration. Three sister repos plug into it. Each is exposed as a
gitignored symlink under `references/repos/` for quick local access (the
real working trees live at `~/Documents/erik/...`):

```
references/repos/servarr               → ~/Documents/erik/servarr
references/repos/hermes-flake          → ~/Documents/erik/hermes-flake
references/repos/home-assistant-config → ~/Documents/erik/code/home-assistant-config
```

Justfile recipes resolve through these symlinks (`readlink -f
references/repos/servarr`); never hard-code the absolute path.

### `servarr` — container stacks on homelab hosts

- Lives at `~/Documents/erik/servarr`. Reachable in-repo via
  `references/repos/servarr`.
- `just sync-servarr <host>` rsyncs
  `references/repos/servarr/machines/<host>/` to
  `erik@<host>:/home/erik/servarr/machines/<host>/`. Excludes `.env` and
  `.env.sops` — those flow through a separate `just push-env <host>` path.
- After a sync, **recreate** (not restart) any containers whose env or
  compose file changed: `docker compose up -d --force-recreate <service>`.
  See `memory/servarr_env_flow.md`.
- Targets today: `kepler`, `discovery`, `orion`. Each host owns a stack
  directory under `references/repos/servarr/machines/<host>/`.
- When adding a new stack: edit
  `references/repos/servarr/machines/<host>/`, run `just sync-stack <host>
  <stack>`, then bring it up on the host.

### `hermes-flake` — hermes-agent package + NixOS module

- Lives at `~/Documents/erik/hermes-flake`. Reachable in-repo via
  `references/repos/hermes-flake`. Vendored as a flake input.
- Provides `packages.hermes-agent` and `nixosModules.hermes-agent`. Consumed
  by `kepler` (AI serving host) and any other host running hermes.
- Upstream version bumps: run `just update-check` then `just update` inside
  `hermes-flake`, build there (`just build`), commit, then update
  `desktop-nixos`'s `flake.lock` (`nix flake lock --update-input
  hermes-flake`) and deploy with `just switch-kepler`.
- TTS / LiteLLM routing nuances are recorded in recent commits and in
  `docs/kepler-ai-serving.md` — follow those before changing wiring.

### `code/home-assistant-config` — HA config on the HA host

- Lives at `~/Documents/erik/code/home-assistant-config`. Reachable in-repo
  via `references/repos/home-assistant-config`. Pushed to the HA instance
  via its own deploy flow (the HA host pulls from the repo; see that repo's
  `README.md` and `hooks/`).
- PR flow: push branches, **do not auto-merge** — wait for the user's
  explicit "merge" (see `memory/feedback_ha_pr_flow.md`).
- Voice-assistant integration touches `kepler` (LiteLLM / piper-openai /
  whisper). When changing voice routing on the HA side, cross-check ports
  and service names against `desktop-nixos/machines/kepler/` and
  `docs/kepler-ai-serving.md`.
- See `memory/ha_voice_assistant.md` for locked decisions and the active
  Phase-1 branch.

### Coupling map

```
desktop-nixos (system config)
├── inputs.servarr      → containers on kepler/discovery/orion
├── inputs.hermes-flake → hermes-agent on kepler
└── deploys / hosts     → kepler also serves HA voice backend
                          ↑
                          home-assistant-config (HA app config)
```

Rule of thumb: when a change touches more than one of these repos, land the
**leaf** repo first (hermes-flake or servarr or home-assistant-config),
then bump the input / sync, then deploy from `desktop-nixos`.

## BMAD-METHOD Integration

Use `/bmalph` to navigate phases. Use `/bmad-help` to discover all commands. Use `/bmalph-status` for a quick overview. See `_bmad/COMMANDS.md` for a full command reference.

### Phases

| Phase | Focus | Key Commands |
|-------|-------|-------------|
| 1. Analysis | Understand the problem | `/create-brief`, `/brainstorm-project`, `/market-research` |
| 2. Planning | Define the solution | `/create-prd`, `/create-ux` |
| 3. Solutioning | Design the architecture | `/create-architecture`, `/create-epics-stories`, `/implementation-readiness` |
| 4. Implementation | Build it | `/sprint-planning`, `/create-story`, then `/bmalph-implement` for Ralph |

### Workflow

1. Work through Phases 1-3 using BMAD agents and workflows (interactive, command-driven)
2. Run `/bmalph-implement` to transition planning artifacts into Ralph format, then start Ralph

### Management Commands

| Command | Description |
|---------|-------------|
| `/bmalph-status` | Show current phase, Ralph progress, version info |
| `/bmalph-implement` | Transition planning artifacts → prepare Ralph loop |
| `/bmalph-upgrade` | Update bundled assets to match current bmalph version |
| `/bmalph-doctor` | Check project health and report issues |

### Available Agents

| Command | Agent | Role |
|---------|-------|------|
| `/analyst` | Analyst | Research, briefs, discovery |
| `/architect` | Architect | Technical design, architecture |
| `/pm` | Product Manager | PRDs, epics, stories |
| `/sm` | Scrum Master | Sprint planning, status, coordination |
| `/dev` | Developer | Implementation, coding |
| `/ux-designer` | UX Designer | User experience, wireframes |
| `/qa` | QA Engineer | Test automation, quality assurance |
