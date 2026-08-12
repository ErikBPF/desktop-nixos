from pathlib import Path


ALIASES = Path(__file__).parents[2] / "modules/shell/_aliases.nix"
AGENT_POLICY = Path(__file__).parents[2] / "modules/dev/agent-policy.md"
CLAUDE = Path(__file__).parents[2] / "modules/dev/claude-code.nix"
CODEX = Path(__file__).parents[2] / "modules/dev/codex.nix"
FLAKE = Path(__file__).parents[2] / "flake.nix"
ZSH = Path(__file__).parents[2] / "modules/shell/zsh.nix"


def test_codex_and_homelab_shortcuts():
    aliases = ALIASES.read_text()

    assert 'c = "codex --dangerously-bypass-approvals-and-sandbox";' in aliases
    assert (
        'cc = "code . ; codex --dangerously-bypass-approvals-and-sandbox";'
        in aliases
    )
    assert 'lab = "cd ~/Documents/erik/homelab";' in aliases


def test_codex_and_claude_share_repository_policy():
    assert AGENT_POLICY.exists()

    policy = AGENT_POLICY.read_text()
    codex = CODEX.read_text()
    claude = CLAUDE.read_text()

    for rule in (
        "Use an explicit repository manifest",
        "Group remaining candidates by their absolute `git-common-dir`",
        "Manual worktrees live under the repository-local `worktrees/` directory",
        "Use Graphify when explicitly requested",
        "Treat merged graphs as discovery-only",
        "Treat graph output as a cache",
        "Never bypass sensitive-file skips",
        "Fall back to `rg` and source files for unsupported formats",
    ):
        assert rule in policy

    assert "builtins.readFile ./agent-policy.md" in codex
    assert '".claude/AGENT_POLICY.md"' in claude
    assert "./agent-policy.md" in claude
    assert "includeClaudeAgentPolicy" in claude
    assert "@AGENT_POLICY.md" in claude


def test_gemini_herdr_entrypoints_and_version():
    aliases = ALIASES.read_text()

    assert 'h = "herdr session attach code";' in aliases
    assert 'hg = "herdr --remote gemini --session code";' in aliases
    assert "hgs = \"ssh -t gemini 'exec herdr session attach code'\";" in aliases
    assert 'herdr.url = "github:ogulcancelik/herdr/v0.7.5";' in FLAKE.read_text()


def test_high_value_shortcuts_without_unsafe_duplicates():
    aliases = ALIASES.read_text()

    for shortcut in (
        'j = "just";',
        'lg = "lazygit";',
        'ld = "lazydocker";',
        'k9 = "k9s";',
        'hl = "herdr session list";',
        'hal = "herdr agent list";',
    ):
        assert shortcut in aliases

    for removed in ("nrs =", "gpu =", "code =", "cx =", "cxc =", "cata ="):
        assert f"\n  {removed}" not in aliases

    zsh = ZSH.read_text()
    assert "clipfiles() {" in zsh
    assert 'command cat -- "$@" | wl-copy' in zsh
