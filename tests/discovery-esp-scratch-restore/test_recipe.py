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


def test_docker_finalize_does_not_pin_volatile_device_names():
    justfile = (Path(__file__).parents[2] / "justfile").read_text()
    recipe = justfile.split("discovery-docker-mirror-finalize:", 1)[1].split(
        "\n# ", 1
    )[0]

    assert "ata-KINGSTON_SA400S37480G_AA000000000000000105-part2" in recipe
    assert "ata-ST4000DM004-2CV104_ZTT25R4M-part1" in recipe
    assert 'findmnt -nro SOURCE -T "$source"' in recipe
    assert "/dev/sda" not in recipe
    assert "/dev/sdb" not in recipe
    assert "/dev/sdc" not in recipe


def test_openbao_d4_backup_refreshes_every_existing_tier():
    justfile = (Path(__file__).parents[2] / "justfile").read_text()
    recipe = justfile.split("backup-discovery-openbao-d4:", 1)[1].split(
        "\n# ", 1
    )[0]

    units = [
        "restic-backups-vault.service",
        "restic-backups-vault-offsite.service",
        "restic-backups-vault-rest.service",
        "restic-backups-vault-b2.service",
    ]
    for unit in units:
        assert unit in recipe
    assert "openbao-restore-drill.service" in recipe
    assert "sha256sum /var/lib/vault-snapshots/openbao.snap" in recipe
    assert "journalctl -u" in recipe
    assert "snapshot=" in recipe
    assert recipe.index(units[0]) < recipe.index(units[1]) < recipe.index(units[2])


def test_identity_backup_covers_tailscale_ssh_and_sops():
    justfile = (Path(__file__).parents[2] / "justfile").read_text()
    recipe = justfile.split("backup-discovery-identity-kepler:", 1)[1].split(
        "\n# ", 1
    )[0]

    assert "var/lib/tailscale/tailscaled.state" in recipe
    assert "etc/ssh/ssh_host_ed25519_key" in recipe
    assert "home/erik/.config/sops/age/keys.txt" in recipe
    assert "--tag discovery-esp-identity" in recipe
    assert "restic dump" in recipe
    assert "sha256sum" in recipe


def test_identity_restore_is_pinned_and_verified_before_service_restart():
    justfile = (Path(__file__).parents[2] / "justfile").read_text()
    recipe = justfile.split("restore-discovery-identity-kepler:", 1)[1].split(
        "\n# ", 1
    )[0]

    assert "868abf42" in recipe
    assert "c6a64318c4b5685b513056d22be3d91c25ae810d6d793c7a9fe400a22ff97c93" in recipe
    assert "SHA256:Y+aJii1TUFtxSY7+LGT0hVBzEatKss/wDHBLFFXk0HE" in recipe
    assert "restic dump" in recipe
    assert "systemctl stop tailscaled-autoconnect.service tailscaled.service" in recipe
    assert recipe.index("sha256sum") < recipe.index("systemctl restart sshd.service")
    assert "tailscale status --json" in recipe


def test_postinstall_storage_check_binds_raid_esp_and_vault():
    justfile = (Path(__file__).parents[2] / "justfile").read_text()
    recipe = justfile.split("verify-discovery-postinstall-storage:", 1)[1].split(
        "\n# ", 1
    )[0]

    assert "ata-KINGSTON_SA400S37480G_AA000000000000000105-part1" in recipe
    assert "ata-KINGSTON_SA400S37480G_AA000000000000000098-part1" in recipe
    assert "d026033d-158d-49ca-9ff9-dd2d5c8a21dc" in recipe
    assert "Data,RAID1:" in recipe
    assert "Metadata,RAID1:" in recipe
    assert "for mount in /boot /home/erik/vault" in recipe


def test_home_restore_is_pinned_quiesced_and_runs_home_manager():
    justfile = (Path(__file__).parents[2] / "justfile").read_text()
    recipe = justfile.split("restore-discovery-home-kepler:", 1)[1].split(
        "\n# ", 1
    )[0]

    assert "6943b508" in recipe
    assert "discovery-mutable-state.tar" in recipe
    assert "d026033d-158d-49ca-9ff9-dd2d5c8a21dc" in recipe
    assert "systemctl stop haos-vm.service docker.service docker.socket" in recipe
    assert "systemctl is-active docker.service" in recipe
    assert "restic dump" in recipe
    assert "home-manager-erik.service" in recipe
    assert "SHA256:Y+aJii1TUFtxSY7+LGT0hVBzEatKss/wDHBLFFXk0HE" in recipe


def test_restore_quiesce_runtime_masks_stateful_substrates():
    justfile = (Path(__file__).parents[2] / "justfile").read_text()
    recipe = justfile.split("quiesce-discovery-restore:", 1)[1].split(
        "\n# ", 1
    )[0]

    assert "systemctl mask --runtime --now" in recipe
    for unit in [
        "docker.service",
        "docker.socket",
        "libvirtd.service",
        "haos-vm.service",
        "openbao.service",
        "vault-agent.service",
    ]:
        assert unit in recipe
    assert 'systemctl stop "${units[@]}"' in recipe


def test_openbao_restore_pins_snapshot_hash_and_verifies_metadata():
    justfile = (Path(__file__).parents[2] / "justfile").read_text()
    recipe = justfile.split("restore-discovery-openbao:", 1)[1].split(
        "\n# ", 1
    )[0]

    assert "315ed0ea" in recipe
    assert "8407ae773697c8511a6d2f2a24f0152dd547a91e7115148c8ecebea4f989ba29" in recipe
    assert "operator init" in recipe
    assert "operator raft snapshot restore -force" in recipe
    assert "/run/secrets/vault_unseal_key" in recipe
    assert "secret/shared/discord" in recipe
    assert "systemctl start vault-agent.service" in recipe
    assert "rm -rf" not in recipe
    assert "pkgs.restic.outPath" in recipe
    assert "journalctl -u openbao.service" in recipe
    assert "ip link add name br-openbao type bridge" in recipe
    assert "172.31.82.1/29" in recipe
    assert 'chown -R erik:users "$work"' in recipe


def test_openbao_restore_resumes_after_snapshot_import_without_reading_root_secrets_as_erik():
    justfile = (Path(__file__).parents[2] / "justfile").read_text()
    recipe = justfile.split("restore-discovery-openbao:", 1)[1].split(
        "\n# ", 1
    )[0]

    assert 'initialized=$(curl -fsS -m 10 http://127.0.0.1:8200/v1/sys/seal-status' in recipe
    assert 'if test "$initialized" = false; then' in recipe
    assert 'sealed=$(curl -fsS -m 10 http://127.0.0.1:8200/v1/sys/seal-status' in recipe
    assert 'if test "$sealed" = true; then' in recipe
    assert "unseal_key=$(sudo cat /run/secrets/vault_unseal_key)" in recipe
    assert "role_id=$(sudo cat /run/secrets/vault_agent_role_id)" in recipe
    assert "secret_id=$(sudo cat /run/secrets/vault_agent_secret_id)" in recipe
    assert "--rawfile key /run/secrets/vault_unseal_key" not in recipe
    assert "--rawfile role_id /run/secrets/vault_agent_role_id" not in recipe
    for stage in ["seal-status", "approle-login", "kv-proof", "vault-agent"]:
        assert f"stage={stage}" in recipe
    assert "for _ in $(seq 1 100); do" in recipe
    assert 'sudo test -s "$path" && break' in recipe


def test_openbao_throwaway_reset_is_guarded_recoverable_and_non_deleting():
    justfile = (Path(__file__).parents[2] / "justfile").read_text()
    recipe = justfile.split("quarantine-discovery-openbao-throwaway:", 1)[1].split(
        "\n# ", 1
    )[0]

    assert "du -sb /var/lib/private/openbao" in recipe
    assert "67108864" in recipe
    assert "mv /var/lib/private/openbao" in recipe
    assert "openbao-d5-throwaway" in recipe
    assert "rm " not in recipe


def test_docker_restore_retains_fresh_root_and_proves_exact_cold_mirror():
    justfile = (Path(__file__).parents[2] / "justfile").read_text()
    recipe = justfile.split("restore-discovery-docker:", 1)[1].split(
        "\n# ", 1
    )[0]

    assert "d026033d-158d-49ca-9ff9-dd2d5c8a21dc" in recipe
    assert "discovery-docker-root.final" in recipe
    assert ".gsd/evidence/discovery-esp/manifest.json" in recipe
    assert "a654304de8d8a29b1986b8ba9f2b3c19a87d58b58768b60c766d4e621ead42b5" in recipe
    assert 'scratch_restore == "passed"' in recipe
    assert "docker-d5-fresh" in recipe
    assert "1073741824" in recipe
    assert "10737418240" in recipe
    assert "config.v2.json" in recipe
    assert 'sudo mv "$destination" "$retained"' in recipe
    assert "systemctl mask --runtime --now" in recipe
    assert 'systemctl mask --runtime --now "${docker_units[@]}" || true' in recipe
    assert "docker-recover.timer" in recipe
    assert 'systemctl stop "${docker_units[@]}"' in recipe
    assert "ConditionPathExists=/run/discovery-docker-restore-start-allowed" in recipe
    assert "systemctl daemon-reload" in recipe
    assert 'test "$(systemctl is-active docker.service' in recipe
    assert "discovery-docker-restore-hold" in recipe
    assert "sudo rsync -aHAXx --numeric-ids --delete --stats" in recipe
    assert "sudo rsync -aHAXxni --numeric-ids --delete" in recipe
    assert 'test -z "$drift"' in recipe
    assert 'test "$source_manifest" = "$expected_manifest"' in recipe
    assert 'test "$destination_manifest" = "$expected_manifest"' in recipe
    assert recipe.count("! -type d -printf") == 2
    assert "systemctl unmask --runtime docker.service docker.socket" in recipe
    assert "systemctl start docker.service" in recipe
    assert "systemctl start docker.service || true" in recipe
    assert "for _ in $(seq 1 300); do" in recipe
    assert "systemctl is-active --quiet docker.service && break" in recipe
    assert "systemctl status docker.service docker.socket" in recipe
    assert "journalctl -u docker.service" in recipe
    assert "DockerRootDir" in recipe
    assert "rm -rf" not in recipe
    for stage in ["preflight", "retain", "rsync", "manifest", "start"]:
        assert f"stage={stage}" in recipe
    assert "vault_uuid=%s marker=%s source=%s docker=%s socket=%s" in recipe


def test_postrestore_resume_starts_declarative_owners_and_proves_harbor_haos():
    justfile = (Path(__file__).parents[2] / "justfile").read_text()
    recipe = justfile.split("resume-discovery-postrestore-substrates:", 1)[1].split(
        "\n# ", 1
    )[0]

    for unit in [
        "docker-recover.timer",
        "openbao-unseal.timer",
        "libvirtd.service",
        "haos-vm.service",
        "harbor.service",
    ]:
        assert unit in recipe
    assert "systemctl unmask --runtime" in recipe
    assert "systemctl start docker-recover.timer openbao-unseal.timer" in recipe
    assert "systemctl restart harbor.service" in recipe
    assert "systemctl start haos-vm.service" in recipe
    assert "http://127.0.0.1:8085/api/v2.0/health" in recipe
    assert 'virsh domstate haos | grep -Fx running' in recipe
    assert "rm " not in recipe


def test_final_gate_checks_openbao_unseal_oneshot_via_timer_and_result():
    justfile = (Path(__file__).parents[2] / "justfile").read_text()
    recipe = justfile.split("verify-discovery-esp:", 1)[1].split(
        "\n# ", 1
    )[0]

    assert "openbao-unseal.timer" in recipe
    assert "systemctl show -p Result --value openbao-unseal.service" in recipe
    assert "openbao openbao-unseal vault-agent" not in recipe
    assert "@{{ip_discovery}}" in recipe
    assert "@127.0.0.1" not in recipe
    for stage in ["openbao", "dns", "grafana", "haos", "failed-units"]:
        assert f"stage={stage}" in recipe


def test_kindle_mirror_passes_pinned_skopeo_and_cosign_path_to_remote_script():
    justfile = (Path(__file__).parents[2] / "justfile").read_text()
    recipe = justfile.split("mirror-kindle version digest:", 1)[1].split(
        "\n# ", 1
    )[0]

    assert "pkgs.skopeo.outPath" in recipe
    assert "pkgs.cosign.outPath" in recipe
    assert "TOOLS_PATH=" in recipe
    assert 'export PATH="$TOOLS_PATH:$PATH"' in recipe


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
    assert "for route in harbor grafana" in recipe
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


def test_discovery_gpu_diagnostic_is_read_only_and_boot_scoped():
    justfile = (Path(__file__).parents[2] / "justfile").read_text()
    recipe = justfile.split("diagnose-discovery-gpu:", 1)[1].split(
        "\n# ", 1
    )[0]

    assert "lspci -nnk" in recipe
    assert "nvidia-smi" in recipe
    assert "lsmod" in recipe
    assert "/dev/nvidia" in recipe
    assert "journalctl -b -k" in recipe
    assert "nvidia-persistenced.service" in recipe
    assert "nvidia-container-toolkit-cdi-generator.service" in recipe
    assert "pkgs.pciutils.outPath" in recipe
    assert "TOOLS_PATH=" in recipe
    assert "systemctl start" not in recipe
    assert "systemctl restart" not in recipe
    assert "systemctl reset-failed" not in recipe


def test_telstar_capture_bootstraps_its_mutable_iac_clone():
    module = (
        Path(__file__).parents[2]
        / "modules/hosts/discovery/telstar-capture.nix"
    ).read_text()

    assert 'WorkingDirectory = home;' in module
    assert 'test -d "${home}/homelab-iac/.git"' in module
    assert "${pkgs.git}/bin/git clone" in module
    assert "git@github_erikbpf:ErikBPF/homelab-iac.git" in module
    assert 'cd "${home}/homelab-iac"' in module


def test_telstar_pause_stops_only_the_retry_unit():
    justfile = (Path(__file__).parents[2] / "justfile").read_text()
    recipe = justfile.split("pause-discovery-telstar:", 1)[1].split(
        "\n# ", 1
    )[0]

    assert "systemctl stop telstar-capture.service" in recipe
    assert "systemctl reset-failed telstar-capture.service" in recipe
    assert "systemctl disable" not in recipe
    assert "rm " not in recipe


def test_hermes_wiki_diagnostic_is_read_only():
    justfile = (Path(__file__).parents[2] / "justfile").read_text()
    recipe = justfile.split("diagnose-hermes-wiki:", 1)[1].split(
        "\n# ", 1
    )[0]

    assert "systemctl status hermes-wiki-clone.service" in recipe
    assert "journalctl -u hermes-wiki-clone.service" in recipe
    assert "systemctl start" not in recipe
    assert "systemctl reset-failed" not in recipe


def test_hermes_wiki_keeps_host_keys_outside_the_checkout():
    module = (
        Path(__file__).parents[2]
        / "modules/hosts/discovery/hermes-wiki.nix"
    ).read_text()

    assert 'StateDirectory = "hermes-wiki-ssh";' in module
    assert "UserKnownHostsFile=/var/lib/hermes-wiki-ssh/known_hosts" in module
    host_git = module.split('export GIT_SSH_COMMAND=', 1)[1].split("\n", 1)[0]
    assert "${wikiDir}/.known_hosts" not in host_git


def test_telstar_state_inventory_is_value_free_and_read_only():
    justfile = (Path(__file__).parents[2] / "justfile").read_text()
    recipe = justfile.split("discovery-telstar-state-inventory:", 1)[1].split(
        "\n# ", 1
    )[0]

    assert "tofu-state-export/oracle/compute-telstar/terraform.tfstate" in recipe
    assert "tofu-state-backup/oracle/compute-telstar/terraform.tfstate" in recipe
    assert "stat -c" in recipe
    assert "sha256sum" in recipe
    assert "cat " not in recipe
    assert "cp " not in recipe
    assert "rm " not in recipe


def test_discovery_gpu_load_is_bounded_and_reports_telemetry():
    justfile = (Path(__file__).parents[2] / "justfile").read_text()
    recipe = justfile.split("test-discovery-gpu-load duration=", 1)[1].split(
        "\n# ", 1
    )[0]

    assert '"$duration" -ge 5' in recipe
    assert '"$duration" -le 900' in recipe
    assert "timeout" in recipe
    assert "testsrc2=size=3840x2160:rate=60" in recipe
    assert "h264_nvenc" in recipe
    assert "--device nvidia.com/gpu=all" in recipe
    assert "--network none" in recipe
    assert "--pull never" in recipe
    assert "utilization.encoder" in recipe
    assert "fan.speed" in recipe
    assert "temperature.gpu" in recipe
    assert "docker volume rm" not in recipe


def test_discovery_gpu_fan_test_is_bounded_and_restores_auto_control():
    justfile = (Path(__file__).parents[2] / "justfile").read_text()
    recipe = justfile.split("test-discovery-gpu-fan percent=", 1)[1].split(
        "\n# ", 1
    )[0]

    assert '"$percent" -ge 30' in recipe
    assert '"$percent" -le 100' in recipe
    assert '"$duration" -le 30' in recipe
    assert 'Option "Coolbits" "4"' in recipe
    assert 'Option "AllowEmptyInitialConfiguration" "True"' in recipe
    assert "GPUFanControlState=1" in recipe
    assert "GPUTargetFanSpeed=$percent" in recipe
    assert "GPUFanControlState=0" in recipe
    assert "trap cleanup EXIT" in recipe
    assert "-nolisten tcp" in recipe
    assert "printf '%s\\n'" in recipe
    assert "/etc/" not in recipe
    assert "rm " not in recipe
