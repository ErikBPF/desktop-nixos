from pathlib import Path


def test_live_preflight_does_not_pin_volatile_device_names():
    justfile = (Path(__file__).parents[2] / "justfile").read_text()
    recipe = justfile.split("discovery-esp-live-preflight:", 1)[1].split(
        "\n# ", 1
    )[0]

    assert "primary_boot=" in recipe
    assert "primary_root=" in recipe
    assert "mirror_part=" in recipe
    assert "vault_part=" in recipe
    assert 'test "$(findmnt -nro SOURCE /boot)" = "$primary_boot"' in recipe
    assert "/dev/sda" not in recipe
    assert "/dev/sdb" not in recipe
    assert "/dev/sdc" not in recipe


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


def test_scratch_refresh_unpublishes_until_zero_drift():
    justfile = (Path(__file__).parents[2] / "justfile").read_text()
    recipe = justfile.split("discovery-docker-scratch-refresh:", 1)[1].split(
        "\n# ", 1
    )[0]

    assert 'if sudo test -e "$scratch"; then' in recipe
    assert 'sudo test ! -e "$pending"' in recipe
    assert 'sudo test -d "$pending"' in recipe
    assert 'sudo mv "$scratch" "$pending"' in recipe
    assert "sudo rsync -aHAXx --numeric-ids --delete --stats" in recipe
    assert "sudo rsync -aHAXxni --numeric-ids --delete" in recipe
    assert 'test -z "$drift"' in recipe
    assert 'sudo mv "$pending" "$scratch"' in recipe


def test_scratch_daemon_is_network_isolated_and_always_stopped():
    justfile = (Path(__file__).parents[2] / "justfile").read_text()
    recipe = justfile.split("discovery-docker-scratch-verify:", 1)[1].split(
        "\n# ", 1
    )[0]

    assert "--property=PrivateNetwork=yes" in recipe
    assert "--property=IPAddressDeny=any" in recipe
    assert "--bridge=none" in recipe
    assert "--iptables=false" in recipe
    assert "--ip-forward=false" in recipe
    assert "--ip-masq=false" in recipe
    assert "config.virtualisation.docker.package.outPath" in recipe
    assert '"$DOCKERD"' in recipe
    assert '--unix-socket "$socket"' in recipe
    assert "api /_ping" in recipe
    assert "api '/containers/json?all=1'" in recipe
    assert "api /images/json" in recipe
    assert "api /volumes" in recipe
    assert 'sudo journalctl -u "$unit" -n 80 --no-pager' in recipe
    assert recipe.count('sudo systemctl stop "$unit" >/dev/null 2>&1 || true') == 2
    assert 'trap \'sudo systemctl stop "$unit" >/dev/null 2>&1 || true\' EXIT' in recipe
    assert 'test "$(systemctl is-active "$unit" 2>/dev/null || true)" = inactive' in recipe


def test_scratch_quiesce_archives_metadata_before_disabling_restart():
    justfile = (Path(__file__).parents[2] / "justfile").read_text()
    recipe = justfile.split("discovery-docker-scratch-quiesce:", 1)[1].split(
        "\n# ", 1
    )[0]

    assert "docker-container-metadata-" in recipe
    assert "config.v2.json" in recipe
    assert "hostconfig.json" in recipe
    assert '.RestartPolicy = {"Name":"no","MaximumRetryCount":0}' in recipe
    assert ".State.Running = false" in recipe
    assert ".HasBeenManuallyStopped = true" in recipe
    assert 'test "$config_count" = "$host_count"' in recipe


def test_postgres_drill_is_full_cluster_isolated_and_value_free():
    justfile = (Path(__file__).parents[2] / "justfile").read_text()
    recipe = justfile.split("discovery-postgres-restore-drill:", 1)[1].split(
        "\n# ", 1
    )[0]

    assert "pg_dumpall" in recipe
    assert "--network none" in recipe
    assert "127.0.0.1" not in recipe
    assert "ssh-keyscan -p 2222" in recipe
    assert "SHA256:Y+aJii1TUFtxSY7+LGT0hVBzEatKss/wDHBLFFXk0HE" in recipe
    assert "StrictHostKeyChecking=yes" in recipe
    assert "ssh -n -p 2222" in recipe
    assert "SELECT datname" in recipe
    assert "pg_extension" in recipe
    assert "information_schema.tables" in recipe
    assert "SELECT *" not in recipe
    assert 'sudo tee "$evidence/result.txt"' in recipe
