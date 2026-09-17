from pathlib import Path
import re
import subprocess


ROOT = Path(__file__).parents[2]
CODEX_MODULE = ROOT / "modules/dev/codex.nix"
CLAUDE_MODULE = ROOT / "modules/dev/claude-code.nix"
SKILLS = ("codehero", "cr", "grill", "ip", "map", "party", "pl", "rv")


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


def test_opencode_loads_shared_agent_policy():
    module = (ROOT / "modules/dev/opencode.nix").read_text()
    assert "builtins.readFile ./agent-policy.md" in module


def test_vendored_graphify_reference_links_resolve():
    for platform in ("codex", "opencode"):
        root = ROOT / "modules/dev/graphify-skills" / platform
        targets = set(re.findall(r"references/[a-z-]+\.md", (root / "SKILL.md").read_text()))
        assert "references/extraction-spec.md" in targets
        for target in targets:
            assert (root / target).is_file(), f"{platform}: missing {target}"
            ignored = subprocess.run(
                ["git", "check-ignore", "-q", str(root / target)], cwd=ROOT
            )
            assert ignored.returncode == 1, f"{platform}: ignored skill dependency {target}"
