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
    assert "ssh -n" in recipe
    assert "SELECT datname" in recipe
    assert "pg_extension" in recipe
    assert "information_schema.tables" in recipe
    assert "SELECT *" not in recipe
    assert 'sudo tee "$evidence/result.txt"' in recipe


def test_redis_drill_proves_empty_networkless_cold_start():
    justfile = (Path(__file__).parents[2] / "justfile").read_text()
    recipe = justfile.split("discovery-redis-cold-start-drill:", 1)[1].split(
        "\n# ", 1
    )[0]

    assert "--network none" in recipe
    assert "DBSIZE" in recipe
    assert "for database in 0 1 2 3 4" in recipe
    assert "dump.rdb" not in recipe
    assert "redis-cli" in recipe


def test_netbird_preflight_reads_pocketid_sqlite_without_values():
    justfile = (Path(__file__).parents[2] / "justfile").read_text()
    recipe = justfile.split("discovery-netbird-state-preflight:", 1)[1].split(
        "\n# ", 1
    )[0]

    assert '"$SQLITE3" -readonly' in recipe
    assert "PRAGMA integrity_check" in recipe
    assert "sqlite_master" in recipe
    assert "SELECT *" not in recipe
    assert "python3" not in recipe
    assert "netbird-management" in recipe
    assert "netbird-pocketid" in recipe


def test_pocketid_repair_refuses_live_process_or_bad_database():
    justfile = (Path(__file__).parents[2] / "justfile").read_text()
    recipe = justfile.split("repair-netbird-pocketid:", 1)[1].split(
        "\n# ", 1
    )[0]

    assert "pgrep" in recipe
    assert "fuser" in recipe
    assert "PRAGMA integrity_check" in recipe
    assert "systemctl reset-failed" in recipe
    assert "systemctl start docker-netbird-pocketid.service" in recipe
    assert ".well-known/openid-configuration" in recipe
    assert "DELETE FROM" not in recipe


def test_pocketid_drill_uses_native_backup_and_network_isolation():
    justfile = (Path(__file__).parents[2] / "justfile").read_text()
    recipe = justfile.split("discovery-pocketid-restore-drill:", 1)[1].split(
        "\n# ", 1
    )[0]

    assert ".backup" in recipe
    assert "ssh -n" in recipe
    assert "--network none" in recipe
    assert "--env-file" in recipe
    assert "/app/pocket-id healthcheck" in recipe
    assert 'sudo docker logs "$name"' in recipe
    assert "DELETE FROM kv WHERE key='application_lock'" in recipe
    assert "name LIKE 'francis_%'" in recipe
    assert "PRAGMA foreign_keys=OFF" in recipe
    assert "DROP VIEW IF EXISTS" in recipe
    assert "DROP TABLE IF EXISTS" in recipe
    assert "SELECT count(*) FROM users" in recipe
    assert "SELECT *" not in recipe


def test_netbird_management_drill_uses_internal_network_and_restored_db():
    justfile = (Path(__file__).parents[2] / "justfile").read_text()
    recipe = justfile.split("discovery-netbird-management-restore-drill:", 1)[
        1
    ].split("\n# ", 1)[0]

    assert "docker network create --internal" in recipe
    assert "postgres-all.sql.gz" in recipe
    assert "netbirdio/management:0.74.3" in recipe
    assert "--network-alias postgres" in recipe
    assert "/run/netbird-management/management.json" in recipe
    assert "NETBIRD_STORE_ENGINE_POSTGRES_DSN" in recipe
    assert "docker port" in recipe
    assert "for table in peers groups users" in recipe
    assert "SELECT count(*) FROM $table" in recipe
    assert "SELECT *" not in recipe


def test_swag_drill_copies_config_and_validates_without_network_or_ports():
    justfile = (Path(__file__).parents[2] / "justfile").read_text()
    recipe = justfile.split("discovery-swag-restore-drill:", 1)[1].split(
        "\n# ", 1
    )[0]

    assert "sudo rsync -aHAXx --numeric-ids" in recipe
    assert "--network none" in recipe
    assert "--entrypoint /usr/sbin/nginx" in recipe
    assert "nginx -t" in recipe
    assert "x509 -checkend" in recipe
    assert "pkey -in" in recipe
    assert "for route in harbor netbird pocket-id grafana" in recipe
    assert "docker port" not in recipe


def test_harbor_preflight_binds_vault_state_and_orion_capacity():
    justfile = (Path(__file__).parents[2] / "justfile").read_text()
    recipe = justfile.split("discovery-harbor-restore-preflight:", 1)[1].split(
        "\n# ", 1
    )[0]

    assert "/home/erik/vault/harbor" in recipe
    assert "d026033d-158d-49ca-9ff9-dd2d5c8a21dc" in recipe
    assert "/projects/recovery/discovery-esp/harbor" in recipe
    assert "findmnt -bnro AVAIL -T /projects" in recipe
    assert "docker ps -a --format json" in recipe
    assert "rsync" not in recipe


def test_harbor_seed_uses_root_rsync_and_pinned_host_key():
    justfile = (Path(__file__).parents[2] / "justfile").read_text()
    recipe = justfile.split("discovery-harbor-restore-seed:", 1)[1].split(
        "\n# ", 1
    )[0]

    assert "just discovery-harbor-restore-preflight" in recipe
    assert "SHA256:Y+aJii1TUFtxSY7+LGT0hVBzEatKss/wDHBLFFXk0HE" in recipe
    assert "sudo rsync -aHAXx --numeric-ids" in recipe
    assert "--rsync-path='sudo rsync'" in recipe
    assert "/home/erik/vault/harbor/" in recipe
    assert "root=/projects/recovery/discovery-esp/harbor" in recipe
    assert "state=$root/state" in recipe
    assert ".harbor-installer/harbor/" in recipe


def test_harbor_finalize_always_restarts_and_proves_zero_drift():
    justfile = (Path(__file__).parents[2] / "justfile").read_text()
    recipe = justfile.split("discovery-harbor-restore-finalize:", 1)[1].split(
        "\n# ", 1
    )[0]

    assert "systemctl stop harbor.service" in recipe
    assert "trap resume EXIT" in recipe
    assert "sudo rsync -aHAXxni --numeric-ids --delete" in recipe
    assert 'test -z "$drift"' in recipe
    assert "systemctl start harbor.service" in recipe
    assert "/api/v2.0/health" in recipe


def test_harbor_inspect_exposes_topology_without_environment():
    justfile = (Path(__file__).parents[2] / "justfile").read_text()
    recipe = justfile.split("discovery-harbor-restore-inspect:", 1)[1].split(
        "\n# ", 1
    )[0]

    assert "docker compose -f" in recipe
    assert "config --format json" in recipe
    assert ".services | to_entries[]" in recipe
    assert "source" in recipe
    assert "published" in recipe
    assert ".environment" not in recipe


def test_harbor_drill_rebuilds_scratch_and_exercises_registry():
    justfile = (Path(__file__).parents[2] / "justfile").read_text()
    recipe = justfile.split("discovery-harbor-restore-drill:", 1)[1].split(
        "\n# ", 1
    )[0]

    assert "./prepare" in recipe
    assert "127.0.0.1:18085" in recipe
    assert "0.0.0.0:18085" in recipe
    assert "COMPOSE_PROJECT_NAME=discovery-harbor-drill" in recipe
    assert "/^    logging:$/" in recipe
    assert "podman login" in recipe
    assert "podman pull" in recipe
    assert "podman push" in recipe
    assert "podman rmi" in recipe
    assert "discovery-esp-drill-" in recipe
    assert "/api/v2.0/system/gc/schedule" in recipe
    assert "compose down" in recipe


def test_haos_preflight_binds_live_disk_vault_and_orion_capacity():
    justfile = (Path(__file__).parents[2] / "justfile").read_text()
    recipe = justfile.split("discovery-haos-restore-preflight:", 1)[1].split(
        "\n# ", 1
    )[0]

    assert "virsh domblklist haos" in recipe
    assert "virsh domstate haos" in recipe
    assert "d026033d-158d-49ca-9ff9-dd2d5c8a21dc" in recipe
    assert "qemu-img" in recipe
    assert "findmnt -bnro AVAIL -T /projects" in recipe
    assert "rsync" not in recipe


def test_haos_seed_uses_pinned_host_key_and_root_rsync():
    justfile = (Path(__file__).parents[2] / "justfile").read_text()
    recipe = justfile.split("discovery-haos-restore-seed:", 1)[1].split(
        "\n# ", 1
    )[0]

    assert "just discovery-haos-restore-preflight" in recipe
    assert "SHA256:Y+aJii1TUFtxSY7+LGT0hVBzEatKss/wDHBLFFXk0HE" in recipe
    assert "--rsync-path='sudo rsync'" in recipe
    assert "/srv/vms/haos_ova-17.1.qcow2" in recipe
    assert "root=/projects/recovery/discovery-esp/haos" in recipe


def test_haos_finalize_always_restarts_and_checks_clone():
    justfile = (Path(__file__).parents[2] / "justfile").read_text()
    recipe = justfile.split("discovery-haos-restore-finalize:", 1)[1].split(
        "\n# ", 1
    )[0]

    assert "virsh shutdown haos" in recipe
    assert "trap resume EXIT" in recipe
    assert "virsh start haos" in recipe
    assert "rsync -aHAXS --inplace" in recipe
    assert "rsync -aHAXSni" in recipe
    assert '"$QEMU_IMG" check' in recipe
    assert "192.168.10.115:8123" in recipe


def test_haos_result_checks_clone_and_production_without_mutation():
    justfile = (Path(__file__).parents[2] / "justfile").read_text()
    recipe = justfile.split("discovery-haos-restore-result:", 1)[1].split(
        "\n# ", 1
    )[0]

    assert '"$QEMU_IMG" check' in recipe
    assert "virsh domstate haos" in recipe
    assert "192.168.10.115:8123" in recipe
    assert "virsh start" not in recipe
    assert "rsync" not in recipe


def test_haos_boot_drill_is_networkless_snapshot_and_pid_scoped():
    justfile = (Path(__file__).parents[2] / "justfile").read_text()
    recipe = justfile.split("discovery-haos-boot-drill:", 1)[1].split(
        "\n# ", 1
    )[0]

    assert "-nic none" in recipe
    assert "-snapshot" in recipe
    assert "edk2-x86_64-code.fd" in recipe
    assert "edk2-i386-vars.fd" in recipe
    assert "virtio-scsi-pci" in recipe
    assert "Home Assistant Operating System" in recipe
    assert 'kill "$(cat "$pidfile")"' in recipe


def test_home_preflight_finds_required_restore_classes_and_capacity():
    justfile = (Path(__file__).parents[2] / "justfile").read_text()
    recipe = justfile.split("discovery-home-restore-preflight:", 1)[1].split(
        "\n# ", 1
    )[0]

    assert ".config/sops/age/keys.txt" in recipe
    assert "/etc/ssh/ssh_host_ed25519_key" in recipe
    assert "servarr" in recipe
    assert "swag" in recipe
    assert "pocket-id" in recipe
    assert "-size +1G" in recipe
    assert "findmnt -bnro AVAIL -T /bulk" in recipe
    assert "restic" not in recipe


def test_home_backup_is_encrypted_and_selectively_verified():
    justfile = (Path(__file__).parents[2] / "justfile").read_text()
    recipe = justfile.split("backup-discovery-home-kepler:", 1)[1].split(
        "\n# ", 1
    )[0]

    assert "RESTIC_PASSWORD_FILE" in recipe
    assert "sftp:erik@" in recipe
    assert "/bulk/backups/discovery-esp-home" in recipe
    assert "tar --one-file-system" in recipe
    assert ".config/sops/age/keys.txt" in recipe
    assert "etc/ssh/ssh_host_ed25519_key" in recipe
    assert ".env.sops" in recipe
    assert "priv-fullchain-bundle.pem" in recipe
    assert "pocket-id.db" in recipe
    assert "model.safetensors" in recipe
    assert "restic dump" in recipe
    assert "sha256sum" in recipe


def test_adguard_restore_preflight_reads_live_mounts_without_environment():
    justfile = (Path(__file__).parents[2] / "justfile").read_text()
    recipe = justfile.split("discovery-adguard-restore-preflight:", 1)[1].split(
        "\n# ", 1
    )[0]

    assert "docker inspect adguard" in recipe
    assert 'Destination == "/opt/adguardhome/work"' in recipe
    assert 'Destination == "/opt/adguardhome/conf"' in recipe
    assert "adguard/adguardhome:v0.108.0-b.83@sha256:" in recipe
    assert "findmnt -bnro AVAIL -T /projects" in recipe
    assert ".Config.Env" not in recipe
    assert "rsync" not in recipe


def test_adguard_seed_copies_live_mounts_with_pinned_host_key():
    justfile = (Path(__file__).parents[2] / "justfile").read_text()
    recipe = justfile.split("discovery-adguard-restore-seed:", 1)[1].split(
        "\n# ", 1
    )[0]

    assert "just discovery-adguard-restore-preflight" in recipe
    assert "SHA256:Y+aJii1TUFtxSY7+LGT0hVBzEatKss/wDHBLFFXk0HE" in recipe
    assert "/var/lib/docker/volumes/discovery-adguard-work/_data/" in recipe
    assert "/home/erik/servarr/machines/discovery/runtime/adguard/" in recipe
    assert "--rsync-path='sudo rsync'" in recipe
    assert "root=/projects/recovery/discovery-esp/adguard" in recipe
    assert 'chmod 0644 "$known_hosts"' in recipe
    assert 'install -d -m 0700 "$root/work" "$root/conf"' in recipe
    assert "test ! -e" not in recipe
    assert "rm -rf" not in recipe


def test_adguard_finalize_bounds_dns_downtime_and_restores_exact_containers():
    justfile = (Path(__file__).parents[2] / "justfile").read_text()
    recipe = justfile.split("discovery-adguard-restore-finalize:", 1)[1].split(
        "\n# ", 1
    )[0]

    assert ".gsd/evidence/p3-dns/runs/20260715T235959Z-d5cf3b5979d8/result.json" in recipe
    assert ".status == \"passed\"" in recipe
    assert "for transport in +notcp +tcp" in recipe
    assert 'dig "$transport"' in recipe
    assert "docker inspect adguard adguard-exporter" in recipe
    assert "docker stop --time 120" in recipe
    assert "trap restart EXIT INT TERM" in recipe
    assert "/var/lib/docker/volumes/discovery-adguard-work/_data/" in recipe
    assert "/home/erik/servarr/machines/discovery/runtime/adguard/" in recipe
    assert "--dry-run --itemize-changes" in recipe
    assert "docker start" in recipe
    assert "dns_ready=false" in recipe
    assert "dns_ready=true" in recipe
    assert 'test "$dns_ready" = true' in recipe
    assert "docker rm" not in recipe
    assert "docker volume" not in recipe


def test_adguard_drill_uses_copied_state_and_loopback_dns_only():
    justfile = (Path(__file__).parents[2] / "justfile").read_text()
    recipe = justfile.split("discovery-adguard-restore-drill:", 1)[1].split(
        "\n# ", 1
    )[0]

    assert "adguard/adguardhome:v0.108.0-b.83@sha256:" in recipe
    assert "/projects/recovery/discovery-esp/adguard/work" in recipe
    assert 'cp -a --reflink=auto "$source_work/." "$work/"' in recipe
    assert "127.0.0.1:15353:53/tcp" in recipe
    assert "127.0.0.1:15353:53/udp" in recipe
    assert "127.0.0.1:18090:80/tcp" in recipe
    assert "for transport in +notcp +tcp" in recipe
    assert "restore-drill.homelab.pastelariadev.com" in recipe
    assert "restore-drill.doubleclick.net" in recipe
    assert "cloudflare.com" in recipe
    assert "flags:.* ad" in recipe
    assert "--network host" not in recipe
    assert "192.168.10.210:53" not in recipe
    assert "docker volume" not in recipe
