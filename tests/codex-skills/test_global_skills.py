from pathlib import Path


ROOT = Path(__file__).parents[2]
CODEX_MODULE = ROOT / "modules/dev/codex.nix"
CLAUDE_MODULE = ROOT / "modules/dev/claude-code.nix"
SKILLS = ("codehero", "grill", "ip", "map", "party", "pl", "rv")


def test_codex_workflow_skills_are_user_global():
    codex_module = CODEX_MODULE.read_text()
    claude_module = CLAUDE_MODULE.read_text()

    for name in SKILLS:
        skill = ROOT / "modules/dev/codex-skills" / name
        assert skill.joinpath("SKILL.md").is_file()
        assert skill.joinpath("agents/openai.yaml").is_file()
        assert (
            f'home.file.".agents/skills/{name}".source = ./codex-skills/{name};'
            in codex_module
        )
        assert (
            f'file.".claude/skills/{name}".source = ./codex-skills/{name};'
            in claude_module
        )

    assert (ROOT / "modules/dev/codex-skills/pl/references/bdd-feature.md").is_file()


def test_global_pl_skill_is_repository_agnostic():
    skill = ROOT / "modules/dev/codex-skills/pl/SKILL.md"

    assert "docs/proposal-index.md" not in skill.read_text()
