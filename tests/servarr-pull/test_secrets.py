from pathlib import Path


MODULE = Path(__file__).parents[2] / "modules/server/orchestration.nix"


def test_pull_always_refreshes_decrypted_env() -> None:
    source = MODULE.read_text()

    assert '-nt "$MACHINE_DIR/.env"' not in source
