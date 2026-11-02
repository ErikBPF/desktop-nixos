# Pull one pinned private HA image on Discovery through the managed reader config.
[positional-arguments]
verify-ha-harbor-reader image:
    #!/usr/bin/env bash
    exec bash scripts/verify-ha-harbor-reader.sh "$1"

test-ha-harbor-reader:
    python3 -m unittest discover -s tests/ha-harbor-reader -p 'test_*.py'

# Rotate exact-path Harbor reader/publisher AppRole credentials into Sops.
capture-harbor-project-iam-approle-secrets:
    #!/usr/bin/env bash
    set -euo pipefail
    token=$(sops --decrypt --extract '["vault_root_token"]' secrets/sops/secrets.yaml)
    for capability in reader publisher; do
      role="svc-homelab-iac-openbao-harbor-project-iam-$capability"
      credentials=$(
        printf '%s\n%s\n' "$token" "$role" | ssh -p 2222 erik@{{ip_discovery}} '
          set -euo pipefail
          IFS= read -r token
          IFS= read -r role
          case "$role" in
            svc-homelab-iac-openbao-harbor-project-iam-reader|svc-homelab-iac-openbao-harbor-project-iam-publisher) ;;
            *) exit 2 ;;
          esac
          cfg=$(mktemp)
          accessor_file="${cfg}.accessors"
          trap "rm -f $cfg $accessor_file" EXIT
          printf "X-Vault-Token: %s\n" "$token" > "$cfg"
          unset token
          chmod 600 "$cfg"
          http_status=$(curl --header @"$cfg" --silent --show-error --request LIST \
            --output "$accessor_file" --write-out "%{http_code}" \
            "http://127.0.0.1:8200/v1/auth/approle/role/$role/secret-id")
          case "$http_status" in
            200) accessors=$(cat "$accessor_file") ;;
            404) accessors='{"data":{"keys":[]}}' ;;
            *) echo "SecretID accessor listing returned HTTP $http_status" >&2; exit 1 ;;
          esac
          while IFS= read -r accessor; do
            jq -cn --arg accessor "$accessor" "{secret_id_accessor: \$accessor}" | \
              curl --header @"$cfg" --silent --show-error --fail --request POST \
                --data @- \
                "http://127.0.0.1:8200/v1/auth/approle/role/$role/secret-id-accessor/destroy" \
                >/dev/null
          done < <(jq -r ".data.keys[]?" <<<"$accessors")
          role_id=$(curl --header @"$cfg" --silent --show-error --fail \
            "http://127.0.0.1:8200/v1/auth/approle/role/$role/role-id" | jq -er .data.role_id)
          secret_id=$(curl --header @"$cfg" --silent --show-error --fail --request POST \
            "http://127.0.0.1:8200/v1/auth/approle/role/$role/secret-id" | jq -er .data.secret_id)
          jq -cn --arg role_id "$role_id" --arg secret_id "$secret_id" "\$ARGS.named"
        '
      )
      key_prefix="openbao_harbor_project_iam_$capability"
      jq -jer .role_id <<<"$credentials" | jq -Rs . \
        | sops set --value-stdin secrets/sops/secrets.yaml \
          "[\"homelab_iac\"][\"${key_prefix}_role_id\"]"
      jq -jer .secret_id <<<"$credentials" | jq -Rs . \
        | sops set --value-stdin secrets/sops/secrets.yaml \
          "[\"homelab_iac\"][\"${key_prefix}_secret_id\"]"
      unset credentials
    done
    unset token
    echo ":: Harbor project-IAM AppRole credentials rotated into sops"

# Capture only the existing IaC publisher's SecretID; never rotate fleet readers.
[positional-arguments]
capture-harbor-fleet-publisher-secret-id confirmation="":
    @python3 scripts/capture-harbor-fleet-publisher-secret-id.py "$1"

# Rotate the fleet-reader publisher plus each projected host's exact-read
# AppRole directly into Sops. Harbor robot values remain OpenBao-only.
capture-harbor-fleet-reader-approle-secrets:
    #!/usr/bin/env bash
    set -euo pipefail
    token=$(sops --decrypt --extract '["vault_root_token"]' secrets/sops/secrets.yaml)
    for identity in publisher discovery endeavour kepler; do
      case "$identity" in
        publisher)
          role=svc-homelab-iac-openbao-harbor-fleet-readers-publisher
          key_prefix=openbao_harbor_fleet_readers_publisher
          key_scope='["homelab_iac"]'
          ;;
        discovery|endeavour|kepler)
          role="svc-desktop-nixos-$identity-harbor-reader"
          key_prefix="openbao_harbor_reader_${identity}"
          key_scope=
          ;;
        *) exit 2 ;;
      esac
      credentials=$(
        printf '%s\n%s\n' "$token" "$role" | ssh -p 2222 erik@{{ip_discovery}} '
          set -euo pipefail
          IFS= read -r token
          IFS= read -r role
          case "$role" in
            svc-homelab-iac-openbao-harbor-fleet-readers-publisher|svc-desktop-nixos-discovery-harbor-reader|svc-desktop-nixos-endeavour-harbor-reader|svc-desktop-nixos-kepler-harbor-reader) ;;
            *) exit 2 ;;
          esac
          cfg=$(mktemp)
          accessor_file="${cfg}.accessors"
          trap "rm -f $cfg $accessor_file" EXIT
          printf "X-Vault-Token: %s\n" "$token" > "$cfg"
          unset token
          chmod 600 "$cfg"
          http_status=$(curl --header @"$cfg" --silent --show-error --request LIST \
            --output "$accessor_file" --write-out "%{http_code}" \
            "http://127.0.0.1:8200/v1/auth/approle/role/$role/secret-id")
          case "$http_status" in
            200) accessors=$(cat "$accessor_file") ;;
            404) accessors='{"data":{"keys":[]}}' ;;
            *) echo "SecretID accessor listing returned HTTP $http_status" >&2; exit 1 ;;
          esac
          while IFS= read -r accessor; do
            jq -cn --arg accessor "$accessor" "{secret_id_accessor: \$accessor}" | \
              curl --header @"$cfg" --silent --show-error --fail --request POST \
                --data @- \
                "http://127.0.0.1:8200/v1/auth/approle/role/$role/secret-id-accessor/destroy" \
                >/dev/null
          done < <(jq -r ".data.keys[]?" <<<"$accessors")
          role_id=$(curl --header @"$cfg" --silent --show-error --fail \
            "http://127.0.0.1:8200/v1/auth/approle/role/$role/role-id" | jq -er .data.role_id)
          secret_id=$(curl --header @"$cfg" --silent --show-error --fail --request POST \
            "http://127.0.0.1:8200/v1/auth/approle/role/$role/secret-id" | jq -er .data.secret_id)
          jq -cn --arg role_id "$role_id" --arg secret_id "$secret_id" "\$ARGS.named"
        '
      )
      jq -jer .role_id <<<"$credentials" | jq -Rs . \
        | sops set --value-stdin secrets/sops/secrets.yaml \
          "${key_scope}[\"${key_prefix}_role_id\"]"
      jq -jer .secret_id <<<"$credentials" | jq -Rs . \
        | sops set --value-stdin secrets/sops/secrets.yaml \
          "${key_scope}[\"${key_prefix}_secret_id\"]"
      unset credentials
    done
    unset token
    echo ":: Harbor fleet-reader AppRole credentials rotated into sops"

# Read-only, value-free evidence for a Harbor activation failure.
harbor-iam-diagnostic:
    #!/usr/bin/env bash
    set -euo pipefail
    ssh -p 2222 erik@{{ip_discovery}} 'bash -s' <<'REMOTE'
    set -u
    systemctl status harbor.service --no-pager -l || true
    systemctl show harbor.service -p ActiveState -p SubState -p Result -p NRestarts
    journalctl -u harbor.service -b --no-pager -n 160 -o short-iso || true
    printf '%s\n' ':: active installer'
    if test -L /home/erik/servarr/machines/discovery/.harbor-installer/current; then
      readlink /home/erik/servarr/machines/discovery/.harbor-installer/current
    else
      printf '%s\n' absent
    fi
    printf '%s\n' ':: harbor containers'
    sudo docker ps -a --format json |
      jq -r 'select((.Names // "") | test("harbor|registry")) |
        [.Names, .State, .Status, .Image] | @tsv'
    REMOTE

# Report only whether Harbor's database owns a non-empty admin credential.
harbor-admin-credential-diagnostic:
    #!/usr/bin/env bash
    set -euo pipefail
    ssh -p 2222 erik@{{ip_discovery}} 'bash -s' <<'REMOTE'
    set -euo pipefail
    sudo docker exec harbor-db psql -X -U postgres -d registry -Atqc \
      "SELECT json_build_object(
        'admin_rows', count(*),
        'salt_present', coalesce(bool_and(length(salt) > 0), false),
        'password_present', coalesce(bool_and(length(password) > 0), false),
        'password_version', max(password_version)
      ) FROM harbor_user WHERE username = 'admin';"
    REMOTE

# Reset only Harbor's DB-backed admin credential to the rendered Vault value.
harbor-admin-password-recover snapshot_id confirmation="":
    #!/usr/bin/env bash
    set -euo pipefail
    snapshot_id={{ quote(snapshot_id) }}
    confirmation={{ quote(confirmation) }}
    [[ $snapshot_id =~ ^[0-9]{8}T[0-9]{6}Z$ ]]
    [[ $confirmation == "reset-db-admin-password" ]] || {
      echo "confirmation must equal reset-db-admin-password" >&2
      exit 64
    }
    ssh -p 2222 erik@{{ip_orion}} bash -s -- "$snapshot_id" <<'REMOTE'
    set -euo pipefail
    target="/projects/recovery/harbor-iam/$1"
    test -d "$target"
    cd "$target"
    sha256sum --check --status SHA256SUMS
    REMOTE
    ssh -p 2222 erik@{{ip_discovery}} 'bash -s' <<'REMOTE'
    set -euo pipefail
    updated=$(sudo docker exec harbor-db psql -X -U postgres -d registry -Atqc \
      "WITH reset AS (
        UPDATE harbor_user SET salt = '', password = ''
        WHERE user_id = 1 AND username = 'admin'
        RETURNING user_id
      ) SELECT count(*) FROM reset;")
    test "$updated" = 1
    sudo docker restart harbor-core >/dev/null
    ready=false
    for _ in $(seq 1 60); do
      if curl -fsS http://127.0.0.1:8085/api/v2.0/health >/dev/null; then
        ready=true
        break
      fi
      sleep 2
    done
    $ready
    REMOTE
    just harbor-iam-preflight vault
    state=$(just harbor-admin-credential-diagnostic)
    jq -e '
      .admin_rows == 1 and
      .salt_present == true and
      .password_present == true and
      .password_version == "pbkdf2_sha256"
    ' <<<"$state" >/dev/null
    echo "Harbor admin credential recovered from the Vault-rendered value"

# Emit only the Harbor IAM metadata needed to decide whether OIDC migration is safe.
harbor-iam-preflight source="vault":
    #!/usr/bin/env bash
    set -euo pipefail
    source={{ quote(source) }}
    case "$source" in
      vault) env_file=/run/vault-agent/harbor.env ;;
      fallback) env_file=/home/erik/servarr/machines/discovery/.env ;;
      *) echo "source must be vault|fallback" >&2; exit 64 ;;
    esac
    ssh -p 2222 erik@{{ip_discovery}} \
      "sudo /run/current-system/sw/bin/bash -s -- --env-file $env_file" \
      < scripts/harbor-iam-preflight.sh

# Capture the pre-mutation Harbor database and sanitized auth metadata on Orion.
harbor-iam-snapshot:
    #!/usr/bin/env bash
    set -euo pipefail
    tmp=$(mktemp -d)
    trap 'rm -rf -- "$tmp"' EXIT
    chmod 700 "$tmp"
    snapshot_id=$(date -u +%Y%m%dT%H%M%SZ)
    target="/projects/recovery/harbor-iam/$snapshot_id"

    just harbor-iam-preflight >"$tmp/harbor-auth.json"
    ssh -p 2222 erik@{{ip_discovery}} \
      'sudo docker exec harbor-db pg_dumpall -U postgres' \
      | gzip -9 >"$tmp/harbor-db.sql.gz"
    chmod 0600 "$tmp/harbor-auth.json" "$tmp/harbor-db.sql.gz"
    (cd "$tmp" && sha256sum harbor-auth.json harbor-db.sql.gz >SHA256SUMS)
    chmod 0600 "$tmp/SHA256SUMS"

    ssh -p 2222 erik@{{ip_orion}} bash -s -- "$target" <<'REMOTE'
    set -euo pipefail
    target=$1
    test ! -e "$target"
    sudo install -d -m 0700 -o erik -g users "$target"
    REMOTE
    scp -P 2222 "$tmp/harbor-auth.json" "$tmp/harbor-db.sql.gz" \
      "$tmp/SHA256SUMS" "erik@{{ip_orion}}:$target/"
    ssh -p 2222 erik@{{ip_orion}} bash -s -- "$target" <<'REMOTE'
    set -euo pipefail
    target=$1
    chmod 0600 "$target/harbor-auth.json" "$target/harbor-db.sql.gz" \
      "$target/SHA256SUMS"
    cd "$target"
    sha256sum --check SHA256SUMS
    REMOTE
    printf 'snapshot_id=%s target=%s\n' "$snapshot_id" "$target"

# Create, validate, or remove the private provider handoff for Harbor IAM IaC.
harbor-iam-bootstrap-provider-handoff action="create" handoff="harbor-iam-bootstrap-provider.secrets.json":
    bash scripts/harbor-iam-provider-handoff.sh {{quote(action)}} {{quote(handoff)}} {{ip_discovery}}

# Read-only Harbor state/identity/capacity gate before copying vault data.
discovery-harbor-restore-preflight:
    #!/usr/bin/env bash
    set -euo pipefail
    source_bytes=$(ssh -p 2222 erik@{{ip_discovery}} 'bash -s' <<'REMOTE'
      set -euo pipefail
      state=/home/erik/vault/harbor
      installer=/home/erik/servarr/machines/discovery/.harbor-installer/current
      test "$(findmnt -nro UUID /home/erik/vault)" = d026033d-158d-49ca-9ff9-dd2d5c8a21dc
      sudo test -d "$state"
      test -d "$installer"
      systemctl is-active --quiet harbor.service
      bytes=$(sudo du -xsb "$state" | cut -f1)
      printf 'state_bytes=%s\n' "$bytes" >&2
      du -sb "$installer" | awk '{print "installer_bytes=" $1}' >&2
      sudo docker ps -a --format json |
        jq -r 'select((.Names // "") | test("harbor|registry")) | [.Names, .State, .Image] | @tsv' >&2
      printf '%s\n' "$bytes"
    REMOTE
    )
    [[ "$source_bytes" =~ ^[0-9]+$ ]]
    ssh -p 2222 erik@{{ip_orion}} "SOURCE_BYTES=$source_bytes bash -s" <<'REMOTE'
      set -euo pipefail
      target=/projects/recovery/discovery-esp/harbor
      available=$(findmnt -bnro AVAIL -T /projects)
      required=$((SOURCE_BYTES * 6 / 5))
      test "$available" -ge "$required"
      printf 'source_bytes=%s available=%s required=%s target=%s\n' \
        "$SOURCE_BYTES" "$available" "$required" "$target"
    REMOTE
    echo ":: PASS: Harbor vault state identified and Orion has restore capacity"

# Seed Harbor vault state + generated installer onto Orion while Harbor runs.
discovery-harbor-restore-seed:
    #!/usr/bin/env bash
    set -euo pipefail
    just discovery-harbor-restore-preflight
    scan=$(mktemp)
    trap 'rm -f "$scan"' EXIT
    ssh-keyscan -p 2222 {{ip_discovery}} >"$scan" 2>/dev/null
    ssh-keygen -lf "$scan" -E sha256 |
      grep -Fq 'SHA256:Y+aJii1TUFtxSY7+LGT0hVBzEatKss/wDHBLFFXk0HE'
    hostkeys=$(base64 -w0 "$scan")
    ssh -p 2222 erik@{{ip_orion}} "HOSTKEYS=$hostkeys bash -s" <<'REMOTE'
      set -euo pipefail
      root=/projects/recovery/discovery-esp/harbor
      state=$root/state
      installer=$root/installer
      known_hosts=$(mktemp)
      printf '%s' "$HOSTKEYS" | base64 -d >"$known_hosts"
      remote_shell="sudo -H -u erik ssh -p 2222 -o BatchMode=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile=$known_hosts"
      trap 'rm -f "$known_hosts"' EXIT
      sudo test ! -e "$state"
      sudo test ! -e "$installer"
      sudo install -d -m 0700 -o root -g root "$state" "$installer"
      set +e
      sudo rsync -aHAXx --numeric-ids --delete --stats \
        --rsync-path='sudo rsync' -e "$remote_shell" \
        erik@{{ip_discovery}}:/home/erik/vault/harbor/ "$state/"
      state_status=$?
      sudo rsync -aHAXx --numeric-ids --delete --stats \
        --rsync-path='sudo rsync' -e "$remote_shell" \
        erik@{{ip_discovery}}:/home/erik/servarr/machines/discovery/.harbor-installer/current/ "$installer/"
      installer_status=$?
      set -e
      case "$state_status" in 0|24) ;; *) exit "$state_status" ;; esac
      case "$installer_status" in 0|24) ;; *) exit "$installer_status" ;; esac
      sudo du -xsb "$state" | awk '{print "state_bytes=" $1}'
      sudo du -xsb "$installer" | awk '{print "installer_bytes=" $1}'
      printf 'state_rsync_status=%s installer_rsync_status=%s\n' \
        "$state_status" "$installer_status"
    REMOTE
    echo ":: PASS: online Harbor restore seed complete; stopped final sync required"

# Briefly stop only Harbor, take the final exact delta, then always restart it.
discovery-harbor-restore-finalize:
    #!/usr/bin/env bash
    set -euo pipefail
    scan=$(mktemp)
    trap 'rm -f "$scan"' EXIT
    ssh-keyscan -p 2222 {{ip_discovery}} >"$scan" 2>/dev/null
    ssh-keygen -lf "$scan" -E sha256 |
      grep -Fq 'SHA256:Y+aJii1TUFtxSY7+LGT0hVBzEatKss/wDHBLFFXk0HE'
    hostkeys=$(base64 -w0 "$scan")
    ssh -p 2222 erik@{{ip_orion}} "HOSTKEYS=$hostkeys bash -s" <<'REMOTE'
      set -euo pipefail
      state=/projects/recovery/discovery-esp/harbor/state
      known_hosts=$(mktemp)
      printf '%s' "$HOSTKEYS" | base64 -d >"$known_hosts"
      options=(-p 2222 -o BatchMode=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile="$known_hosts")
      remote_shell="sudo -H -u erik ssh ${options[*]}"
      sudo test -d "$state"
      resume() {
        ssh -n "${options[@]}" erik@{{ip_discovery}} \
          'sudo systemctl start harbor.service' >/dev/null 2>&1 || true
        rm -f "$known_hosts"
      }
      trap resume EXIT
      ssh -n "${options[@]}" erik@{{ip_discovery}} '
        set -euo pipefail
        test "$(findmnt -nro UUID /home/erik/vault)" = d026033d-158d-49ca-9ff9-dd2d5c8a21dc
        systemctl is-active --quiet harbor.service
        sudo systemctl stop harbor.service
        test "$(systemctl is-active harbor.service 2>/dev/null || true)" = inactive
      '
      started=$(date +%s)
      sudo rsync -aHAXx --numeric-ids --delete --stats \
        --rsync-path='sudo rsync' -e "$remote_shell" \
        erik@{{ip_discovery}}:/home/erik/vault/harbor/ "$state/"
      drift=$(sudo rsync -aHAXxni --numeric-ids --delete \
        --rsync-path='sudo rsync' -e "$remote_shell" \
        erik@{{ip_discovery}}:/home/erik/vault/harbor/ "$state/")
      test -z "$drift" || { printf '%s\n' "$drift" >&2; exit 1; }
      ssh -n "${options[@]}" erik@{{ip_discovery}} 'sudo systemctl start harbor.service'
      ssh -n "${options[@]}" erik@{{ip_discovery}} '
        set -euo pipefail
        healthy=false
        for _ in $(seq 1 60); do
          if curl --fail --silent --max-time 3 http://127.0.0.1:8085/api/v2.0/health |
            jq -e ".status == \"healthy\"" >/dev/null 2>&1; then
            healthy=true
            break
          fi
          sleep 1
        done
        "$healthy"
        systemctl is-active harbor.service
      '
      trap - EXIT
      rm -f "$known_hosts"
      printf 'final_sync_seconds=%s drift=zero\n' "$(( $(date +%s) - started ))"
    REMOTE
    echo ":: PASS: Harbor final copy is exact and production API recovered"

# Print only generated Harbor topology needed to design an isolated boot.
discovery-harbor-restore-inspect:
    #!/usr/bin/env bash
    set -euo pipefail
    ssh -p 2222 erik@{{ip_orion}} 'bash -s' <<'REMOTE'
      set -euo pipefail
      installer=/projects/recovery/discovery-esp/harbor/installer
      sudo test -f "$installer/docker-compose.yml"
      sudo docker compose -f "$installer/docker-compose.yml" config --format json |
        jq -c '
          .services | to_entries[] |
          {
            service: .key,
            image: .value.image,
            mounts: [.value.volumes[]? | {type, source, target}],
            ports: [.value.ports[]? | {target, published, protocol}],
            networks: (.value.networks // {})
          }'
    REMOTE

# Rebuild copied Harbor state on loopback, then pull, push, and delete a scratch tag.
discovery-harbor-restore-drill:
    #!/usr/bin/env bash
    set -euo pipefail
    ssh -p 2222 erik@{{ip_orion}} 'sudo bash -s' <<'REMOTE'
      set -euo pipefail
      root=/projects/recovery/discovery-esp/harbor
      source_installer=$root/installer
      installer=$root/drill-installer
      state=$root/state
      tag="discovery-esp-drill-$(date +%s)"
      export COMPOSE_PROJECT_NAME=discovery-harbor-drill
      cleanup() {
        test -z "${authfile:-}" || rm -f "$authfile"
        cd "$installer" 2>/dev/null &&
          sudo -E docker compose down --remove-orphans >/dev/null 2>&1 || true
      }
      trap cleanup EXIT
      sudo test -d "$state"
      sudo test -x "$source_installer/prepare"
      sudo rm -rf "$installer"
      sudo cp -a "$source_installer" "$installer"
      sudo chown -R erik:users "$installer"
      cd "$installer"
      sed -i \
        -e 's|^hostname:.*|hostname: harbor-drill.invalid|' \
        -e 's|^  port: 8085$|  port: 18085|' \
        -e "s|^data_volume:.*|data_volume: $state|" \
        -e "s|^    location:.*|    location: $root/log|" \
        harbor.yml
      if grep -q '^external_url:' harbor.yml; then
        sed -i 's|^external_url:.*|external_url: http://127.0.0.1:18085|' harbor.yml
      fi
      sudo install -d -m 0700 "$root/log"
      bash ./prepare
      awk '
        /^    logging:$/ { skip=1; next }
        skip && (/^[^ ]/ || /^  [^ ]/ || /^    [[:alnum:]_-]+:/) { skip=0 }
        !skip
      ' docker-compose.yml >docker-compose.yml.tmp
      mv docker-compose.yml.tmp docker-compose.yml
      sed -i \
        -e 's|18085:8080|127.0.0.1:18085:8080|' \
        docker-compose.yml
      sudo -E docker compose up -d
      healthy=false
      for _ in $(seq 1 120); do
        if curl --fail --silent --max-time 3 \
          http://127.0.0.1:18085/api/v2.0/health |
          jq -e '.status == "healthy"' >/dev/null 2>&1; then
          healthy=true
          break
        fi
        sleep 1
      done
      "$healthy"
      password=$(sed -n 's/^harbor_admin_password:[[:space:]]*//p' harbor.yml)
      test -n "$password"
      auth="admin:$password"
      image=library/kindle-dash
      source="docker://127.0.0.1:18085/$image:v0.3.4"
      target="docker://127.0.0.1:18085/$image:$tag"
      authfile=$(mktemp)
      rm -f "$authfile"
      printf '%s' "$password" |
        podman login --authfile "$authfile" --tls-verify=false \
          -u admin --password-stdin 127.0.0.1:18085 >/dev/null
      source=${source#docker://}
      target=${target#docker://}
      podman pull --authfile "$authfile" --tls-verify=false "$source" >/dev/null
      podman tag "$source" "$target"
      podman push --authfile "$authfile" --tls-verify=false "$target" >/dev/null
      podman rmi "$target" >/dev/null
      podman pull --authfile "$authfile" --tls-verify=false "$target" >/dev/null
      curl --fail --silent -o /dev/null -u "$auth" \
        http://127.0.0.1:18085/api/v2.0/system/gc/schedule
      curl --fail --silent -u "$auth" -X DELETE \
        "http://127.0.0.1:18085/api/v2.0/projects/library/repositories/kindle-dash/artifacts/$tag"
      rm -f "$authfile"
      status=$(sudo -E docker compose ps)
      printf '%s\n' "$status"
      ! grep -Fq '0.0.0.0:18085' <<<"$status"
    REMOTE
    echo ":: PASS: isolated Harbor restored; auth, pull, push, delete, and GC metadata passed"
