from pathlib import Path


JUSTFILE = Path(__file__).parents[2] / "justfile"


def test_kepler_disk_diagnostic_is_read_only():
    recipe = JUSTFILE.read_text()

    assert "diagnose-kepler-disk:" in recipe
    assert "btrfs filesystem usage /" in recipe
    assert "du -x -d2 -B1 /nix /var /home" in recipe
    assert "/home/erik/.local /home/erik/.cache /home/erik/openwakeword-training" in recipe
    assert "zfs list -o name,mountpoint,used,available,recordsize" in recipe
    assert "systemctl cat microvm@cp-1.service" in recipe
    assert "btrfs device stats /" in recipe
    assert "btrfs scrub status /" in recipe
    assert "_TRANSPORT=kernel" in recipe
    assert 'grep -Ei "BTRFS|Structure needs cleaning|I/O error|corrupt"' in recipe
    assert "btrfs scrub start" not in recipe
    assert "btrfs check --repair" not in recipe


def test_model_cache_cleanup_has_exact_targets():
    recipe = JUSTFILE.read_text()

    assert "clean-kepler-model-cache:" in recipe
    assert "rm -rf -- /home/erik/ha-hf /home/erik/hf-cache" in recipe
