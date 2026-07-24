from pathlib import Path


def test_scratch_restore_preflight_is_read_only_and_targets_orion_projects():
    justfile = (Path(__file__).parents[2] / "justfile").read_text()
    recipe = justfile.split("discovery-docker-scratch-preflight:", 1)[1].split(
        "\n# ", 1
    )[0]

    assert 'scratch=/projects/recovery/discovery-esp/docker-root' in recipe
    assert 'test "$available" -ge "$required"' in recipe
    assert "test ! -e \"$scratch\"" in recipe
    assert "ssh -p 2222 erik@{{ip_orion}}" in recipe
    assert "| cut -f1" in recipe
    assert "mkdir" not in recipe
    assert "rsync" not in recipe


def test_scratch_restore_runs_root_rsync_with_erik_ssh():
    justfile = (Path(__file__).parents[2] / "justfile").read_text()
    recipe = justfile.split("discovery-docker-scratch-restore:", 1)[1].split(
        "\n# ", 1
    )[0]

    assert "just discovery-docker-scratch-preflight" in recipe
    assert "sudo install -d -m 0700 -o root -g root" in recipe
    assert "sudo rsync -aHAXx --numeric-ids --delete --stats" in recipe
    assert "--rsync-path='sudo rsync'" in recipe
    assert "sudo -H -u erik ssh -p 2222" in recipe
    assert "ssh-keyscan -p 2222" in recipe
    assert "SHA256:Y+aJii1TUFtxSY7+LGT0hVBzEatKss/wDHBLFFXk0HE" in recipe
    assert "UserKnownHostsFile=$known_hosts" in recipe
    assert "erik@{{ip_discovery}}:/home/erik/vault/migration/discovery-docker-root/" in recipe
    assert "sudo rsync -aHAXxni --numeric-ids --delete" in recipe
