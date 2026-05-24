# Obsidian + Karpathy LLM Wiki — Setup Guide

This guide turns your existing vault (`~/Documents/erik/obsidian/vault`) into a Karpathy-style LLM Wiki with fully declarative nix config, automated git sync to `git@github_erikbpf:ErikBPF/vault.git`, and 18 community plugins installed from GitHub releases as nix derivations.

The nix side is already done. This document covers the manual one-shot steps you must run yourself.

---

## 0. What the nix changes do

After your next rebuild:

- `modules/desktop/obsidian.nix`:
  - Writes declarative configs to `.obsidian/`: `app.json`, `appearance.json`, `core-plugins.json`, `community-plugins.json`, `hotkeys.json`, `bookmarks.json`, `templates.json`.
  - **Fetches 18 community plugins** from GitHub releases as nix derivations (sha256-pinned), symlinks `main.js` / `manifest.json` / `styles.css` into `.obsidian/plugins/<id>/`.
  - Seeds the vault on first run with folders (`raw/`, `wiki/`, `log/`, `templates/`) + files (`AGENTS.md`, `index.md`, `log.md`, `inbox.md`, `.gitignore`, templater templates).
  - Seeds per-plugin `data.json` for `obsidian-git`, `obsidian-linter`, `dataview`, `obsidian-tasks-plugin`, `templater-obsidian`, `quickadd`, `periodic-notes` (only if missing — Obsidian owns the file after first write).
  - **Configures git remote** `origin = git@github_erikbpf:ErikBPF/vault.git` on every activation.
  - Strips stale `.obsidian/*.backup` noise.
- `modules/desktop/obsidian-sync.nix` installs a systemd user service + timer that auto-commits and rebases your vault every 30 minutes.

What nix does NOT do:

- Provide API keys for the `copilot` or `obsidian-llm-wiki` plugins.
- Configure your SSH key for the GitHub remote.
- Do the initial push (first commit history must be created once by you).

---

## 1. Rebuild

```fish
cd ~/Documents/erik/desktop-nixos
just build
```

Already done if you're reading this after I implemented it. To verify:

```fish
ls ~/Documents/erik/obsidian/vault/.obsidian/plugins/obsidian-llm-wiki/
# expect: main.js → /nix/store/...  manifest.json → ...  styles.css → ...

git -C ~/Documents/erik/obsidian/vault remote -v
# expect: origin git@github_erikbpf:ErikBPF/vault.git (fetch + push)
```

---

## 2. Plugins (no UI install needed)

All 18 plugins are installed declaratively via nix. The full list:

| Plugin | Repo | Version |
|---|---|---|
| obsidian-llm-wiki | green-dalii/obsidian-llm-wiki | 1.10.2 |
| smart-connections | brianpetro/obsidian-smart-connections | 4.5.0 |
| quickadd | chhoumann/quickadd | 2.12.1 |
| periodic-notes | liamcain/obsidian-periodic-notes | 1.0.0-beta.3 |
| obsidian-advanced-uri | Vinzent03/obsidian-advanced-uri | 1.46.1 |
| recent-files-obsidian | tgrosinger/recent-files-obsidian | 1.7.9 |
| paste-url-into-selection | denolehov/obsidian-url-into-selection | 1.11.4 |
| calendar | liamcain/obsidian-calendar-plugin | 1.5.10 |
| copilot | logancyang/obsidian-copilot | 3.3.3 |
| dataview | blacksmithgu/obsidian-dataview | 0.5.68 |
| obsidian-excalidraw-plugin | zsviczian/obsidian-excalidraw-plugin | 2.23.3 |
| obsidian-git | Vinzent03/obsidian-git | 2.38.3 |
| obsidian-icon-folder | FlorianWoelki/obsidian-iconize | 2.14.7 |
| obsidian-linter | platers/obsidian-linter | 1.31.2 |
| obsidian-style-settings | obsidian-community/obsidian-style-settings | 1.0.9 |
| obsidian-tasks-plugin | obsidian-tasks-group/obsidian-tasks | 8.0.0 |
| omnisearch | scambier/obsidian-omnisearch | 1.29.2 |
| templater-obsidian | SilentVoid13/Templater | 2.20.5 |

**Bumping a plugin version**: edit `pluginSpecs.<id>.version` in `modules/desktop/obsidian.nix`, run `just build`. Nix will print the expected new hash; paste into the relevant `hashes` entry, re-run.

**Adding a plugin**: append a new entry to `pluginSpecs`. Get hashes by running:

```fish
nix store prefetch-file --json https://github.com/<owner>/<repo>/releases/download/<version>/main.js | jq -r .hash
```

Repeat for `manifest.json` and (if present) `styles.css`. Add entry to `pluginSpecs`. Rebuild.

**Dropped**: `obsidian-markmind` (redundant with canvas), `table-editor-obsidian` (release 0.23.2 ships no binary). The `.obsidian/plugins/obsidian-markmind/` and `.obsidian/plugins/table-editor-obsidian/` directories still exist on disk from prior installs but won't load — safe to delete:

```fish
rm -rf ~/Documents/erik/obsidian/vault/.obsidian/plugins/{obsidian-markmind,table-editor-obsidian}
```

---

## 3. Initial git push

The remote `git@github_erikbpf:ErikBPF/vault.git` is wired. You still need to create the GitHub repo and push the first commit.

```fish
# 3a. Create the GitHub repo (if it doesn't exist yet)
gh repo create ErikBPF/vault --private --description "Karpathy LLM wiki vault"

# 3b. Clean up + first commit + push
cd ~/Documents/erik/obsidian/vault
rm -f .obsidian/*.backup
rm -rf .obsidian/plugins/obsidian-markmind .obsidian/plugins/table-editor-obsidian
git add -A
git commit -m "chore(vault): seed Karpathy LLM wiki layout + declarative plugins"
git push -u origin main
git branch --set-upstream-to=origin/main main
```

If `gh repo create` says the repo already exists, just skip 3a.

---

## 4. Verify the systemd sync timer

```fish
systemctl --user list-timers obsidian-vault-sync
# Next should be ~30 min out, Last should be recent

systemctl --user start obsidian-vault-sync.service
journalctl --user -u obsidian-vault-sync.service -n 30
# expect: fetch + rebase + push, exit 0
```

If you see `Permission denied (publickey)`: the SSH agent isn't reachable from the systemd user manager. Fix:

```fish
systemctl --user import-environment SSH_AUTH_SOCK
systemctl --user restart obsidian-vault-sync.service
```

Persist by adding to your fish config (or wherever the agent socket is set):

```fish
set -gx SSH_AUTH_SOCK $XDG_RUNTIME_DIR/ssh-agent.socket  # adjust to your agent
```

Then `systemctl --user import-environment SSH_AUTH_SOCK` once per session — or wire it via `systemd.user.services.<your-agent>` with `PassEnvironment` if you want it fully automatic.

---

## 5. Configure plugin secrets (API keys)

These can't be nix-managed without a secret manager. Open Obsidian → Settings.

### copilot

`Settings → Copilot`: paste your Anthropic / OpenAI key. Set default model to `claude-opus-4-7` for long-context wiki ops.

### obsidian-llm-wiki

`Settings → LLM Wiki`: select provider (Anthropic recommended for Karpathy parity — long-context not RAG), paste key, set model. Point its working dir at the vault root.

> ⚠️ Keys land in `.obsidian/plugins/<id>/data.json` — fine for a *private* repo. If the remote ever flips public, add to vault `.gitignore`:
>
> ```
> .obsidian/plugins/copilot/data.json
> .obsidian/plugins/obsidian-llm-wiki/data.json
> ```
>
> Or wire via `sops-nix` later if you want them fully nix-managed.

---

## 6. Daily hotkeys (already bound by nix)

| Action | Shortcut | What it does |
|---|---|---|
| Ingest URL | `Cmd+Shift+I` | QuickAdd capture → `inbox.md` |
| Process inbox | `Cmd+Shift+P` | QuickAdd template → triggers agent task |
| Lint wiki | `Cmd+Shift+L` | QuickAdd template → triggers lint task |
| Git push | `Cmd+Shift+K` | Manual push via obsidian-git |
| Git pull | `Cmd+Shift+J` | Manual pull via obsidian-git |
| Graph view | `Cmd+Shift+G` | Open graph |
| Smart connections | `Cmd+Shift+S` | Semantic sidebar |

`Cmd+Shift+P` opens `templates/process-inbox.md` — a prompt for your LLM agent (Copilot, obsidian-llm-wiki, or external Claude Code). Read `AGENTS.md` in the vault for the full Karpathy ruleset the agent should follow.

---

## 7. First Karpathy ingest

Smoke-test the full flow:

1. `Cmd+Shift+I` → paste a URL + title. Lands in `inbox.md`.
2. `Cmd+Shift+P` → opens `process-inbox.md` template. Your LLM agent reads it, fetches the URL, writes verbatim source into `raw/`, summarizes into `wiki/`, updates `index.md`, appends to `log.md`.
3. Watch graph view as cross-references appear.
4. Within 30 min the systemd timer pushes to `origin/main`. Or `Cmd+Shift+K` to push immediately.

The wiki "grows from questions, not just from saved content" — Karpathy's phrase. Every `query` op should ask the agent: *"is this answer worth a new wiki page?"* If yes, the agent creates one and links it.

---

## 8. Multi-device

The systemd sync timer assumes one writer at a time. Two machines editing within the same 30-min window risks rebase conflict.

Mitigations:

- `Cmd+Shift+J` before each session to pull.
- Reduce `OnUnitActiveSec` from `30m` to `5m` in `modules/desktop/obsidian-sync.nix` if you sync often.
- Or disable the timer and use manual `Cmd+Shift+K` / `Cmd+Shift+J` only:
  ```fish
  systemctl --user disable --now obsidian-vault-sync.timer
  ```

---

## 9. Optional — encryption

Skip if the GitHub repo stays private and the vault contains no secrets in markdown.

If you start storing journal / credentials / sensitive notes, add `git-crypt`:

```fish
nix-shell -p git-crypt
cd ~/Documents/erik/obsidian/vault
git-crypt init
echo 'secrets/** filter=git-crypt diff=git-crypt' >> .gitattributes
git-crypt export-key ~/.config/sops/obsidian-vault-key
# back this key up in sops-nix or 1Password — losing it = losing the vault
git add .gitattributes
git commit -m "chore(vault): enable git-crypt for secrets/**"
```

---

## 10. Troubleshooting

| Symptom | Fix |
|---|---|
| Plugin missing in Obsidian UI after rebuild | Restart Obsidian — it scans `.obsidian/plugins/` on launch. |
| `.backup` files reappear in `.obsidian/` | Obsidian tried to write a nix-symlink config. Activation removes them each rebuild. If they keep coming back mid-session, move that file from `home.file` to a mutable activation seed in `obsidian.nix`. |
| Daily note misses template | Check `templater` enabled and `.obsidian/plugins/templater-obsidian/data.json` has `trigger_on_file_creation: true`. Delete `data.json` to re-seed from nix. |
| Sync timer fails on `Permission denied (publickey)` | `systemctl --user import-environment SSH_AUTH_SOCK` then restart timer. |
| Rebase conflict in `journalctl` | Open vault, resolve, `git rebase --continue`, push. Timer resumes. |
| `obsidian-llm-wiki` writes nonsense | Switch to a long-context model. Karpathy's pattern *requires* long context — RAG is the antipattern. |
| Plugin hash mismatch on rebuild | GitHub release file changed (re-uploaded). Run `nix store prefetch-file --json <url>` to get new hash, update `pluginSpecs.<id>.hashes` in `obsidian.nix`. |

---

## 11. Updating plugin versions

```fish
# pick a plugin, edit version field
$EDITOR modules/desktop/obsidian.nix

# bump pluginSpecs.<id>.version = "X.Y.Z";

# rebuild — fails with expected hash
just build

# copy the printed hash into pluginSpecs.<id>.hashes."main.js"
# repeat for manifest.json + styles.css if it complains
just build
```

---

## 12. Updating AGENTS.md schema

`AGENTS.md` is the contract between you and the LLM. The vault file is authoritative. The seed in `obsidian.nix` is only used on first creation — edits to the vault file persist.

To re-seed from nix (overwriting your edits):

```fish
rm ~/Documents/erik/obsidian/vault/AGENTS.md
just build
```

---

## Reference

- Karpathy gist: <https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f>
- obsidian-llm-wiki plugin: <https://github.com/green-dalii/obsidian-llm-wiki>
- Ar9av agent framework: <https://github.com/Ar9av/obsidian-wiki>
- jhinpan FTS5 + lint pattern: <https://gist.github.com/jhinpan/16f240dfce4b45532f28b5df829bc887>
- Home-manager native obsidian module (alternative): <https://github.com/nix-community/home-manager/blob/master/modules/programs/obsidian.nix>
