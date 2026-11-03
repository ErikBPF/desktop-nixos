from pathlib import Path


ROOT = Path(__file__).parents[2]
JUSTFILE = "\n".join(p.read_text() for p in [ROOT / "justfile", *sorted((ROOT / "just").glob("*.just"))])


def test_checkout_repair_excludes_untracked_runtime_state():
    recipes = JUSTFILE
    start = recipes.index("repair-servarr-checkout target:")
    block = recipes[start : recipes.index("\n\n", start)]

    assert "git -c safe.directory=\"$repo\" -C \"$repo\" ls-files -z" in block
    assert '[[ -e "$path" || -L "$path" ]]' in block
    assert 'chown -R erik:users "$repo/.git"' in block
    assert 'chown -R erik:users "$repo"' not in block
