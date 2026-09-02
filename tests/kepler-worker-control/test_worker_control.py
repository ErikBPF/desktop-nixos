from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def test_stop_worker_is_allowlisted_and_verified() -> None:
    justfile = (ROOT / "justfile").read_text()
    recipe = justfile.split("stop-k3s-worker target:", 1)[1].split(
        "\nrestart-k3s-worker target:", 1
    )[0]

    assert "w-1|w-2|w-3" in recipe
    assert "microvm@{{target}}.service" in recipe
    assert "systemctl stop" in recipe
    assert "systemctl is-active" in recipe
    assert "cp-1" not in recipe
    assert "kubectl --context homelab drain" in recipe
    assert recipe.index("kubectl --context homelab drain") < recipe.index(
        "systemctl stop"
    )


def test_restart_worker_uncordons_after_ready() -> None:
    justfile = (ROOT / "justfile").read_text()
    recipe = justfile.split("restart-k3s-worker target:", 1)[1].split(
        "\n# Read-only proof", 1
    )[0]

    assert recipe.index("condition=Ready") < recipe.index("kubectl --context homelab uncordon")
