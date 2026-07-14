from pathlib import Path
import re


JUSTFILE = Path(__file__).parents[2] / "justfile"


def recipe(name: str) -> str:
    text = JUSTFILE.read_text()
    match = re.search(
        rf"^{re.escape(name)}(?: [^\n:]*)?:\n(?P<body>(?:^[ \t]+.*\n|^\n)*)",
        text,
        re.MULTILINE,
    )
    assert match, f"missing {name} recipe"
    return match.group("body")


def test_build_only_realizes_toplevel_without_activation():
    body = recipe("build")
    assert "nix build --no-link" in body
    assert ".#nixosConfigurations.{{target}}.config.system.build.toplevel" in body
    assert "nixos-rebuild" not in body
    assert " switch " not in body


def test_switch_keeps_explicit_local_activation_path():
    body = recipe("switch")
    assert "nixos-rebuild switch --flake .#{{target}}" in body
    assert 'BUILDERS="$(just _builders {{target}})"' in body
    assert "builders-use-substitutes true" in body


def test_builder_preflight_is_explicit_and_target_aware():
    body = recipe("builder-preflight")
    assert 'BUILDERS="$(just _builders {{target}})"' in body
    assert 'sudo ./scripts/builder-preflight.sh "$BUILDERS"' in body
    assert "builder-preflight" not in recipe("build")
    assert "builder-preflight" not in recipe("switch")
