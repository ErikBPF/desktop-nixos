# Persistent umbrella sessions

**Status:** Workflow agreed; terminal alternatives reviewed 2026-09-07.
Apollo has native Herdr/tmux. Native Orion Herdr/tmux and agent tools were activated
2026-09-07; Gemini was removed. Client shortcut deployment remains host-specific.

Personal sessions start in `~/Documents/erik/homelab` on Orion. Work sessions
start in `~/Documents/nstech/dataplatform` on Apollo. These umbrella repos hold
context and delegate implementation to sister repos. Keep that entry point
even when a task spans several repositories.

Use one session per visible task/window: `l1`, `l2`, `w1`,
`w2`. Multiple sessions may use the same umbrella checkout, but simultaneous
edits to the same files still require coordination. Assign independent changes
to separate implementation worktrees; do not require one session per child repo.

## First option: named Herdr sessions

From two desktop terminals, these Apollo examples start or attach independent
sessions with the same initial umbrella directory:

```sh
ssh -t apollo 'cd ~/Documents/nstech/dataplatform && exec herdr --session w1'
ssh -t apollo 'cd ~/Documents/nstech/dataplatform && exec herdr --session w2'
```

Run each command in its own window. Existing session cwd and layout are retained;
changing the launch directory does not move an already-running shell. The analogous native Orion entry uses `orion`, the homelab path
and `l1`/`l2`.

For locally integrated clipboard behavior, attach an established session with
`herdr --remote apollo --session w1`. Keep client/server versions pinned
together. Herdr Plus provides layouts, Navigator finds sessions/remotes; neither
is needed merely to have two independent servers. Start agents on demand.

The shared Herdr module declares these aliases; each starts or attaches the
named session from its umbrella:

```sh
alias w1="ssh -t apollo 'cd ~/Documents/nstech/dataplatform && exec herdr --session w1'"
alias w2="ssh -t apollo 'cd ~/Documents/nstech/dataplatform && exec herdr --session w2'"
alias l1="ssh -t orion 'cd ~/Documents/erik/homelab && exec herdr --session l1'"
alias l2="ssh -t orion 'cd ~/Documents/erik/homelab && exec herdr --session l2'"
```

Native Orion is active. Keep task names
in tabs/windows; keep these umbrella entry aliases stable across sister repos.

Two full UI clients attached to the same pinned Herdr v0.8.0 session share its
application focus. Named sessions avoid that coupling. `Ctrl+b q` detaches;
server stop kills the processes. Reboot restores only supported persisted state,
not arbitrary running jobs. See [Herdr persistence](https://herdr.dev/docs/persistence-remote/).

## Alternative: ordinary tmux sessions

Use separate task sessions for independent processes:

```sh
ssh -t apollo 'cd ~/Documents/nstech/dataplatform && exec tmux new-session -A -s w1'
ssh -t apollo 'cd ~/Documents/nstech/dataplatform && exec tmux new-session -A -s w2'
```

With the current default prefix, `Ctrl+b c` creates a window, `Ctrl+b w` chooses
one, and `Ctrl+b d` detaches. Avoid the legacy `tmux-repo` seven-pane launcher
for this workflow; it imposes a layout and auto-launches agents. Its deployed
safety fix refuses to replace an existing custom session.

If both desktop terminals should share the same windows but select different
ones, use grouped sessions instead of the separate-session setup above. On Apollo,
create these once, using names that are not already occupied:

```sh
tmux new-session -d -s w1 -c ~/Documents/nstech/dataplatform
tmux new-window -d -t w1 -n second -c ~/Documents/nstech/dataplatform
tmux new-session -d -s w2 -t w1
```

Then attach from separate desktop windows:

```sh
ssh -t apollo 'exec tmux attach-session -t "=w1"'
ssh -t apollo 'exec tmux attach-session -t "=w2"'
```

Grouped sessions share window contents and changes, but their selected window
is independent. Viewing the same window still shares its pane selection and
running processes; terminal sizing also needs a representative two-window
check. A detached isolated test verified shared window IDs with independent
current-window selection. See the [tmux manual](https://github.com/tmux/tmux/blob/master/tmux.1).

## Git and Syncthing

Keep Git history local to each clone. Syncthing may mirror unfinished files,
with Orion writing personal sets and Apollo writing work sets. Do not open a
secondary as a writer just because its files look synchronized: first stop the
old writer, check convergence, preserve local dirty/staged/untracked work and
unpublished refs, reconcile the Git base, then take over deliberately.

Recovery mirrors outside active clones are the safer initial shape. Live
single-writer worktree synchronization is also possible, but requires that
handoff discipline. Never synchronize live `.git`, worktree metadata, credentials
or agent databases. A receive-only setting is not an ownership lock or backup.

## Operations

Project shells select toolchains; project recipes own their deploy/test loops.
Keep the host/session, Git branch and Kubernetes context visible. Read-only
Apollo diagnosis remains `just diagnose-apollo-worklab` from desktop-nixos.
Orion automatic upgrades are disabled until this migration lands on main.
Re-enable in source without automatic reboot; maintenance must account for sessions. Closing a laptop should preserve
work; rebooting its execution host interrupts processes.

Gemini retirement is authorized. Legacy `hg`, `hgs`, `hlab` and `hr` now enter
Orion `l1`; `hdap` enters Apollo `w1`. The per-repository Gemini launcher is removed.

## Isolated disconnect smoke check

Use a dedicated tmux socket so existing user sessions are untouched. Refuse an
existing probe server. Each command uses a separate SSH connection:

```sh
ssh -p 2222 erik@orion 'if tmux -L codex-cutover-20260907 list-sessions >/dev/null 2>&1; then exit 1; fi; tmux -L codex-cutover-20260907 new-session -d -s probe -c /home/erik/Documents/erik/homelab "sleep 120"'
ssh -p 2222 erik@orion 'tmux -L codex-cutover-20260907 has-session -t "=probe" && tmux -L codex-cutover-20260907 list-panes -t "=probe" -F "#{pane_current_path}"'
ssh -p 2222 erik@orion 'tmux -L codex-cutover-20260907 kill-server'
```

Repeat on Apollo with host `apollo` and directory
`/home/erik/Documents/nstech/dataplatform`. This checks the tmux fallback and
umbrella location across client disconnects; it does not prove Herdr agent
restoration or process survival across host reboot.

The isolated tmux disconnect probe passed on Orion and Apollo on 2026-09-07;
each preserved its umbrella cwd across separate SSH connections.
