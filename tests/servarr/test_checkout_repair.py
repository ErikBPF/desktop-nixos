from pathlib import Path


JUSTFILE = Path(__file__).parents[2] / "justfile"


def test_checkout_repair_excludes_untracked_runtime_state():
    recipes = JUSTFILE.read_text()
    start = recipes.index("repair-servarr-checkout target:")
    block = recipes[start : recipes.index("\n\n", start)]

    assert "git -c safe.directory=\"$repo\" -C \"$repo\" ls-files -z" in block
    assert 'chown -R erik:users "$repo/.git"' in block
    assert 'chown -R erik:users "$repo"' not in block
