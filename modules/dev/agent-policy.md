## Repository discovery and worktrees

- Use an explicit repository manifest such as `repos.json` before scanning
  sibling directories.
- A directly targeted checkout is valid, including a linked worktree.
- During sibling or multi-repository discovery, skip `worktrees/`. Group remaining candidates by their absolute `git-common-dir` and prefer the checkout whose absolute `git-dir` equals its `git-common-dir`.
- Manual worktrees live under the repository-local `worktrees/` directory.
  Add that path to `.gitignore` and `.graphifyignore` before creating them.
- Tool-managed and temporary worktrees remain valid. Never move or remove them
  automatically. Inspect dirty state first; when cleanup is requested, use
  `git worktree remove` rather than deleting the directory directly.

## Graphify

- Use Graphify when explicitly requested or when the current repository has a
  `graphify-out/graph.json`; query an existing graph before reading broadly.
- Prefer per-repository queries. Treat merged graphs as discovery-only unless
  cross-repository edges exist.
- Build canonical repository graphs by default. Build a worktree-specific graph
  only when explicitly requested.
- Treat graph output as a cache; verify operational, security, ownership, and
  current-state claims in source.
- Never bypass sensitive-file skips or index `*.secrets.json`, `.env*`,
  Sops/Vault material, certificates, or credentials.
- Fall back to `rg` and source files for unsupported formats.
