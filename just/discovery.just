# Remote switches go through deploy-rs (magic rollback + build on Orion). The
# generic `deploy` recipe below stays as the escape hatch (plain nixos-rebuild,
# local build, no rollback) if deploy-rs itself is ever the problem.
switch-discovery:
    just deploy-rs discovery

# Read-only activation-failure evidence for Discovery's AppArmor unit. Fixed
# unit and allowlisted generation links keep this safe for unattended triage.
discovery-apparmor-diagnostic:
    #!/usr/bin/env bash
    set -euo pipefail
    ssh -p 2222 erik@{{ip_discovery}} 'bash -s' <<'REMOTE'
      set -euo pipefail
      echo ":: generation identity"
      for link in /run/current-system /run/booted-system /nix/var/nix/profiles/system; do
        if [ -e "$link" ]; then
          printf '%s=%s\n' "$link" "$(readlink -f "$link")"
        else
          printf '%s=absent\n' "$link"
        fi
      done
      echo ":: apparmor status"
      sudo systemctl status apparmor.service --no-pager -l || true
      echo ":: apparmor current-boot journal"
      sudo journalctl -b -u apparmor.service --no-pager -n 160 -o short-iso || true
    REMOTE

# P3 read-only gate before enabling Kepler CoreDNS. Kepler :53 must be free;
# the existing vanguard tailnet resolver must still answer over UDP and TCP.
p3-dns-preflight:
    #!/usr/bin/env bash
    set -euo pipefail
    KEPLER=$(just _host-ip kepler)
    VANGUARD_TAIL=$(jq -r '.hosts.vanguard.tailscaleIp' fleet.json)
    listeners=$(ssh -p 2222 erik@"$KEPLER" \
      "sudo ss -H -lntu 'sport = :53' | grep -Ev '127\\.0\\.0\\.(53|54)(%lo)?:53|\\[::1\\]:53' || true")
    test -z "$listeners" || { echo "BLOCKED: Kepler non-loopback port 53 already in use" >&2; exit 1; }
    for transport in +notcp +tcp; do
      test "$(dig "$transport" +short +time=3 +tries=1 @"$VANGUARD_TAIL" grafana.homelab.pastelariadev.com A)" = "192.168.10.250"
      test -n "$(dig "$transport" +short +time=3 +tries=1 @"$VANGUARD_TAIL" example.com A)"
    done
    echo ":: P3 preflight OK — Kepler :53 free; vanguard UDP/TCP DNS healthy"

# P3 direct-secondary verification after a Kepler deployment. DHCP remains
# untouched until this gate also passes after reboot.
p3-dns-verify:
    #!/usr/bin/env bash
    set -euo pipefail
    KEPLER=$(just _host-ip kepler)
    for transport in +notcp +tcp; do
      test "$(dig "$transport" +short +time=3 +tries=1 @"$KEPLER" grafana.homelab.pastelariadev.com A)" = "192.168.10.250"
      test -n "$(dig "$transport" +short +time=3 +tries=1 @"$KEPLER" example.com A)"
      dig "$transport" +time=3 +tries=1 @"$KEPLER" grafana.homelab.pastelariadev.com AAAA | grep -q 'status: NOERROR'
    done
    ssh -p 2222 erik@"$KEPLER" '
      set -euo pipefail
      test "$(systemctl is-active coredns.service)" = active
      ! sudo ss -H -lntu "sport = :53" | grep -Eq "(^|[[:space:]])(0\\.0\\.0\\.0|\\[::\\]):53"
      test "$(systemctl show coredns.service -P NRestarts)" = 0
    '
    echo ":: P3 direct secondary OK — Kepler UDP/TCP fleet/external DNS healthy"

# Refresh the OpenBao snapshot across every declared tier, then prove restore.
backup-discovery-openbao-d4:
    #!/usr/bin/env bash
    set -euo pipefail
    IP="$(just _host-ip discovery)"
    ssh -p 2222 erik@"$IP" 'bash -s' <<'REMOTE'
      set -euo pipefail
      units=(
        restic-backups-vault.service
        restic-backups-vault-offsite.service
        restic-backups-vault-rest.service
        restic-backups-vault-b2.service
      )
      for unit in "${units[@]}"; do
        sudo systemctl start "$unit"
        snapshot=$(sudo journalctl -u "$unit" -n 200 --no-pager -o cat |
          sed -n \
            -e 's/.*snapshot \([0-9a-f]\{8,\}\) saved.*/\1/p' \
            -e 's/.*"snapshot_id":"\([0-9a-f]\{8,\}\)".*/\1/p' |
          tail -1)
        test -n "$snapshot"
        printf 'unit=%s snapshot=%s\n' "$unit" "$snapshot"
      done
      sudo sha256sum /var/lib/vault-snapshots/openbao.snap
      sudo systemctl start openbao-restore-drill.service
      test "$(systemctl show openbao-restore-drill.service --property=Result --value)" = success
    REMOTE
    echo ":: PASS: fresh OpenBao snapshot copied to every tier and restored"

openbao-restore-drill:
    IP="$(just _host-ip discovery)"; ssh -p 2222 erik@"$IP" 'sudo systemctl start openbao-restore-drill.service && { sudo systemctl status openbao-restore-drill.service --no-pager || true; }'

openbao-restore-drill-diagnose:
    IP="$(just _host-ip discovery)"; ssh -p 2222 erik@"$IP" 'sudo systemctl status openbao-restore-drill.service --no-pager -l || true; sudo journalctl -u openbao-restore-drill.service --no-pager -n 100'

# Re-prove peer-dependent Discovery units after a fleet reboot. The unrelated
# IaC drift failure is left for its owning repo and only reset for this window.
recover-discovery-reboot-blockers:
    #!/usr/bin/env bash
    set -euo pipefail
    IP="$(just _host-ip discovery)"
    ssh -p 2222 erik@"$IP" 'bash -s' <<'REMOTE'
    set -euo pipefail
    for unit in mnt-nfs-fast.mount restic-backups-vault-offsite.service restic-check-voyager.service; do
      sudo systemctl reset-failed "$unit"
      sudo systemctl start "$unit" || {
        sudo systemctl status "$unit" --no-pager -l || true
        sudo journalctl -u "$unit" -n 80 --no-pager || true
        exit 1
      }
    done
    sudo systemctl reset-failed homelab-iac-drift.service
    test -z "$(systemctl --failed --no-legend)"
    REMOTE

# Reboot Discovery and prove the host transitioned down then up.
reboot-discovery:
    #!/usr/bin/env bash
    set -euo pipefail
    IP="$(just _host-ip discovery)"
    set +e
    ssh -p 2222 -o BatchMode=yes -o ConnectionAttempts=1 erik@"$IP" sudo systemctl reboot
    reboot_status=$?
    set -e
    if (( reboot_status != 0 && reboot_status != 255 )); then
        echo ":: discovery reboot dispatch failed with status $reboot_status" >&2
        exit 1
    fi
    echo ":: waiting for discovery to stop..."
    saw_down=0
    for _ in $(seq 1 30); do
        if ! ssh -p 2222 -o BatchMode=yes -o ConnectionAttempts=1 -o ConnectTimeout=2 erik@"$IP" true 2>/dev/null; then
            saw_down=1
            break
        fi
        sleep 1
    done
    if (( saw_down == 0 )); then
        echo ":: discovery never became unreachable after reboot dispatch" >&2
        exit 1
    fi
    echo ":: waiting for discovery to return..."
    deadline=$((SECONDS + 240))
    while (( SECONDS < deadline )); do
        if ssh -p 2222 -o BatchMode=yes -o ConnectionAttempts=1 -o ConnectTimeout=2 erik@"$IP" true 2>/dev/null; then
            echo ":: discovery reachable"
            just verify discovery "$IP" 2222 erik
            exit 0
        fi
        sleep 2
    done
    echo ":: discovery did not return within 240s" >&2
    exit 1

# List OpenBao audit devices and safe transport options only.
openbao-audit-status:
    #!/usr/bin/env bash
    set -euo pipefail
    token=$(sops --decrypt --extract '["vault_root_token"]' secrets/sops/secrets.yaml)
    printf '%s\n' "$token" | ssh -p 2222 erik@{{ip_discovery}} '
      set -euo pipefail
      IFS= read -r token
      cfg=$(mktemp)
      trap "rm -f $cfg" EXIT
      printf "X-Vault-Token: %s\\n" "$token" > "$cfg"
      unset token
      chmod 600 "$cfg"
      curl --header @"$cfg" --silent --show-error --fail http://127.0.0.1:8200/v1/sys/audit |
        jq -c ".data | to_entries | map({path:.key,type:.value.type,options:(.value.options | {file_path,log_raw,hmac_accessor})})"
    '

deploy-discovery:
    #!/usr/bin/env bash
    set -euo pipefail
    export NIX_CONFIG="builders = $(just _builders discovery)
    max-jobs = 1
    builders-use-substitutes = true"
    mkdir -p /tmp/nixos-extra/var/lib/sops-staging/
    cp ~/.config/sops/age/keys.txt /tmp/nixos-extra/var/lib/sops-staging/age-keys.txt
    chmod 600 /tmp/nixos-extra/var/lib/sops-staging/age-keys.txt
    trap 'rm -rf /tmp/nixos-extra' EXIT
    # NOTE: No LUKS on Discovery
    # Target: nixos@192.168.10.210 (NixOS ISO, port 22)
    # WARNING: sda and sdc will be wiped. sdb (/home/erik/vault) is NOT touched by disko.
    # Before running: boot Discovery from NixOS ISO, confirm device paths with:
    #   ssh nixos@192.168.10.210 'lsblk -d -o NAME,SIZE,TYPE,MODEL | sort'
    nix run github:nix-community/nixos-anywhere -- \
        --flake .#discovery \
        --extra-files /tmp/nixos-extra \
        --show-trace \
        --generate-hardware-config nixos-generate-config \
            ./modules/hosts/discovery/_hw-generated.nix \
        nixos@192.168.10.210

# Inspect OpenBao ingress without reading credentials or logging request bodies.
discovery-openbao-access-diagnostic:
    #!/usr/bin/env bash
    set -euo pipefail
    ssh -p 2222 -o BatchMode=yes -o ConnectTimeout=8 erik@{{ip_discovery}} 'bash -s' <<'REMOTE'
    set -euo pipefail
    systemctl is-active openbao
    sudo -n iptables-save -t nat
    sudo -n iptables -S ts-forward
    sudo -n docker inspect swag | jq '.[0].NetworkSettings.Networks | with_entries(.value |= {IPAddress, Gateway})'
    sudo -n docker port swag
    systemctl show openbao -p User -p Group -p NoNewPrivileges -p ProtectSystem -p ProtectHome -p PrivateTmp -p CapabilityBoundingSet -p MemoryDenyWriteExecute
    curl -sS --max-time 5 -o /dev/null -w 'openbao_local=%{http_code}\n' http://127.0.0.1:8200/v1/sys/health
    sudo -n docker exec swag sh -c '
      nginx -t
      grep -E "^[[:space:]]*(server_name|allow|deny|set_real_ip_from|real_ip_header|real_ip_recursive) " /config/nginx/proxy-confs/openbao.subdomain.conf /config/nginx/nginx.conf
      tail -n 500 /config/log/nginx/error.log | sed -n "s/.*access forbidden by rule, client: \([^,]*\), server: openbao[^,]*,.*/openbao_denied_client=\1/p" | sort -u
    '
    REMOTE

# Snapshot before the controlled restart needed to load a new immutable config.
restart-openbao-with-backup:
    #!/usr/bin/env bash
    set -euo pipefail
    ssh -p 2222 -o BatchMode=yes -o ConnectTimeout=8 erik@{{ip_discovery}} 'bash -s' <<'REMOTE'
    set -euo pipefail
    test "$(systemctl show openbao -p LogsDirectory --value)" = openbao
    sudo -n systemctl start restic-backups-vault.service
    test "$(systemctl show restic-backups-vault -p Result --value)" = success
    sudo -n systemctl restart openbao.service
    sudo -n systemctl start openbao-unseal.service
    curl -fsS --retry 15 --retry-delay 1 --retry-max-time 30 --max-time 10 http://127.0.0.1:8200/v1/sys/health | jq -e '.initialized and (.sealed | not)' >/dev/null
    systemctl is-active openbao vault-agent
    REMOTE

# Repair only the empty audit file created outside OpenBao's idmapped mount.
# No audit data is removed; fail closed on any different state.
repair-openbao-empty-audit-owner:
    #!/usr/bin/env bash
    set -euo pipefail
    ssh -p 2222 -o BatchMode=yes -o ConnectTimeout=8 erik@{{ip_discovery}} 'bash -s' <<'REMOTE'
    set -euo pipefail
    systemctl is-active --quiet openbao.service
    test "$(systemctl show openbao -p DynamicUser --value)" = yes
    pid=$(systemctl show openbao -p MainPID --value)
    test "$pid" -gt 1
    uid=$(awk '/^Uid:/ {print $2}' "/proc/$pid/status")
    gid=$(awk '/^Gid:/ {print $2}' "/proc/$pid/status")
    sudo -n nsenter -t "$pid" -m -- bash -s -- "$uid" "$gid" <<'NAMESPACE'
    set -euo pipefail
    file=/var/log/openbao/audit.json
    test -f "$file" && test ! -L "$file" && test ! -s "$file"
    test "$(stat -c '%a' "$file")" = 600
    test "$(stat -Lc '%u:%g' /var/log/openbao)" = "$1:$2"
    test "$(stat -c '%u:%g' "$file")" != "$1:$2"
    chown -- "$1:$2" "$file"
    test "$(stat -c '%u:%g:%a' "$file")" = "$1:$2:600"
    NAMESPACE
    test "$(systemctl show openbao -p MainPID --value)" = "$pid"
    sudo -n systemctl kill --kill-whom=main --signal=HUP openbao.service
    for attempt in {1..15}; do
        status=$(curl -sS --max-time 5 -o /dev/null -w '%{http_code}' http://127.0.0.1:8200/v1/secret/data/shared/discord)
        if [ "$status" = 403 ] && sudo -n test -s /var/log/openbao/audit.json; then
            echo 'PASS: audit ownership repaired; denied request audited'
            exit 0
        fi
        sleep 1
    done
    echo 'FAIL: audit did not resume' >&2
    exit 1
    REMOTE

# No token: prove transport works, secrets require auth, and headers cannot spoof access.
verify-openbao-hardening:
    #!/usr/bin/env bash
    set -euo pipefail
    curl -fsS --max-time 10 https://openbao.homelab.pastelariadev.com/v1/sys/health | jq -e '.initialized and (.sealed | not)' >/dev/null
    test "$(curl -sS --max-time 10 -o /dev/null -w '%{http_code}' https://openbao.homelab.pastelariadev.com/v1/secret/data/shared/discord)" = 403
    ssh -p 2222 -o BatchMode=yes -o ConnectTimeout=8 erik@{{ip_discovery}} 'bash -s' <<'REMOTE'
    set -euo pipefail
    status=$(sudo -n docker exec swag curl -sS --max-time 10 -o /dev/null -w '%{http_code}' --resolve openbao.homelab.pastelariadev.com:443:127.0.0.1 -H 'X-Forwarded-For: 100.100.0.2' https://openbao.homelab.pastelariadev.com/v1/sys/health)
    test "$status" = 403
    test "$(sudo -n stat -Lc '%a' /var/log/openbao/audit.json)" = 600
    sudo -n test -s /var/log/openbao/audit.json
    pid=$(systemctl show openbao -p MainPID --value)
    test "$pid" -gt 1
    uid=$(awk '/^Uid:/ {print $2}' "/proc/$pid/status")
    gid=$(awk '/^Gid:/ {print $2}' "/proc/$pid/status")
    test "$(sudo -n nsenter -t "$pid" -m -- stat -Lc '%u:%g:%a' /var/log/openbao/audit.json)" = "$uid:$gid:600"
    systemctl is-active openbao vault-agent
    REMOTE
    just openbao-audit-status

# Value-free exporter diagnostic: allowlisted family presence only.
discovery-adguard-exporter-diagnostic:
    #!/usr/bin/env bash
    set -euo pipefail
    IP="$(just _host-ip discovery)"
    ssh -p 2222 erik@"$IP" \
      'sudo -n /run/current-system/sw/bin/discovery-stateful-adguard-inventory exporter-families'

# Stream a fresh full-cluster dump to Orion, restore it into a networkless
# disposable PostgreSQL container, and print metadata counts only.
discovery-postgres-restore-drill:
    #!/usr/bin/env bash
    set -euo pipefail
    scan=$(mktemp)
    trap 'rm -f "$scan"' EXIT
    ssh-keyscan -p 2222 {{ip_discovery}} >"$scan" 2>/dev/null
    if ! ssh-keygen -lf "$scan" -E sha256 |
      grep -Fq 'SHA256:Y+aJii1TUFtxSY7+LGT0hVBzEatKss/wDHBLFFXk0HE'; then
      ssh-keygen -lf "$scan" -E sha256
      exit 1
    fi
    hostkeys=$(base64 -w0 "$scan")
    ssh -p 2222 erik@{{ip_orion}} "HOSTKEYS=$hostkeys bash -s" <<'REMOTE'
      set -euo pipefail
      image='postgres:18.4@sha256:3a82e1f56c8f0f5616a11103ac3d47e632c3938698946a7ad26da0df1334744a'
      stamp=$(date +%Y-%m-%d_%H%M%S)
      evidence="/projects/recovery/discovery-esp/postgres/$stamp"
      dump="$evidence/postgres-all.sql.gz"
      name="discovery-postgres-drill-$stamp"
      known_hosts=$(mktemp)
      started=$(date +%s)
      printf '%s' "$HOSTKEYS" | base64 -d >"$known_hosts"
      sudo install -d -m 0700 -o root -g root "$evidence"
      trap 'rm -f "$known_hosts"; sudo docker rm -f "$name" >/dev/null 2>&1 || true' EXIT
      ssh -n -p 2222 -o BatchMode=yes -o StrictHostKeyChecking=yes \
        -o UserKnownHostsFile="$known_hosts" erik@{{ip_discovery}} '
        set -euo pipefail
        cd /home/erik/servarr/machines/discovery
        user=$(sed -n "s/^POSTGRES_USER=//p" .env | tail -1)
        test -n "$user"
        sudo docker exec postgres pg_dumpall -U "$user"
      ' | gzip | sudo tee "$dump" >/dev/null
      sudo test -s "$dump"
      sudo gzip -t "$dump"
      sudo docker image inspect "$image" >/dev/null 2>&1 || sudo docker pull "$image"
      sudo docker run -d --network none --name "$name" \
        -e POSTGRES_PASSWORD=drill-only "$image" >/dev/null
      ready=false
      for _ in $(seq 1 60); do
        if sudo docker exec "$name" pg_isready -U postgres >/dev/null 2>&1; then
          ready=true
          break
        fi
        sleep 1
      done
      "$ready"
      sudo gzip -dc "$dump" |
        sudo docker exec -i "$name" psql -v ON_ERROR_STOP=1 -U postgres postgres >/dev/null
      roles=$(sudo docker exec "$name" psql -AtU postgres postgres \
        -c 'SELECT count(*) FROM pg_roles')
      databases=$(sudo docker exec "$name" psql -AtU postgres postgres \
        -c "SELECT datname FROM pg_database WHERE datallowconn AND NOT datistemplate ORDER BY 1")
      test -n "$databases"
      {
        printf 'roles=%s\n' "$roles"
        while IFS= read -r database; do
          extensions=$(sudo docker exec "$name" psql -AtU postgres "$database" \
            -c 'SELECT count(*) FROM pg_extension')
          tables=$(sudo docker exec "$name" psql -AtU postgres "$database" \
            -c "SELECT count(*) FROM information_schema.tables WHERE table_schema NOT IN ('pg_catalog','information_schema')")
          rows=$(sudo docker exec "$name" psql -AtU postgres "$database" \
            -c 'SELECT coalesce(sum(n_live_tup),0)::bigint FROM pg_stat_user_tables')
          printf 'database=%s extensions=%s tables=%s representative_rows=%s\n' \
            "$database" "$extensions" "$tables" "$rows"
        done <<<"$databases"
        sudo sha256sum "$dump"
        printf 'dump=%s duration_seconds=%s\n' "$dump" "$(( $(date +%s) - started ))"
      } | sudo tee "$evidence/result.txt"
      sudo chmod 0600 "$evidence/result.txt"
    REMOTE
    echo ":: PASS: full PostgreSQL dump restored and inspected on isolated Orion"

# Print the newest value-free PostgreSQL drill report.
discovery-postgres-restore-drill-result:
    #!/usr/bin/env bash
    set -euo pipefail
    ssh -p 2222 erik@{{ip_orion}} '
      latest=$(sudo find /projects/recovery/discovery-esp/postgres -mindepth 2 -maxdepth 2 -name result.txt -printf "%T@ %p\n" | sort -nr | head -1 | cut -d" " -f2-)
      test -n "$latest"
      sudo cat "$latest"
    '

# Prove the declared Redis cache layer starts empty without restored state.
discovery-redis-cold-start-drill:
    #!/usr/bin/env bash
    set -euo pipefail
    ssh -p 2222 erik@{{ip_orion}} 'bash -s' <<'REMOTE'
      set -euo pipefail
      image='redis:8.8.0-alpine@sha256:9d317178eceac8454a2284a9e6df2466b93c745529947f0cd42a0fa9609d7005'
      name="discovery-redis-drill-$(date +%s)"
      trap 'sudo docker rm -f "$name" >/dev/null 2>&1 || true' EXIT
      sudo docker image inspect "$image" >/dev/null 2>&1 || sudo docker pull "$image"
      sudo docker run -d --network none --name "$name" "$image" \
        redis-server --requirepass drill-only >/dev/null
      ready=false
      for _ in $(seq 1 30); do
        if sudo docker exec "$name" redis-cli -a drill-only PING 2>/dev/null |
          grep -qx PONG; then
          ready=true
          break
        fi
        sleep 1
      done
      "$ready"
      sudo docker inspect "$name" |
        jq -e '.[0].HostConfig.NetworkMode == "none"' >/dev/null
      for database in 0 1 2 3 4; do
        keys=$(sudo docker exec "$name" redis-cli -a drill-only -n "$database" DBSIZE 2>/dev/null)
        test "$keys" = 0
        printf 'database=%s keys=%s\n' "$database" "$keys"
      done
    REMOTE
    echo ":: PASS: isolated Redis cold-started empty; no production state restored"

# Copy SWAG state and validate nginx/certificates on networkless Orion.
discovery-swag-restore-drill:
    #!/usr/bin/env bash
    set -euo pipefail
    openssl=$(nix eval --raw .#nixosConfigurations.orion.pkgs.openssl.outPath)/bin/openssl
    scan=$(mktemp)
    trap 'rm -f "$scan"' EXIT
    ssh-keyscan -p 2222 {{ip_discovery}} >"$scan" 2>/dev/null
    if ! ssh-keygen -lf "$scan" -E sha256 |
      grep -Fq 'SHA256:Y+aJii1TUFtxSY7+LGT0hVBzEatKss/wDHBLFFXk0HE'; then
      ssh-keygen -lf "$scan" -E sha256
      exit 1
    fi
    hostkeys=$(base64 -w0 "$scan")
    ssh -p 2222 erik@{{ip_orion}} "HOSTKEYS=$hostkeys OPENSSL=$openssl bash -s" <<'REMOTE'
      set -euo pipefail
      image='lscr.io/linuxserver/swag:5.6.0-ls467@sha256:ce148c3794d2dfcb63eaeed55c516324e800349f8cd57e49ec0eb312fe75f01d'
      stamp=$(date +%Y-%m-%d_%H%M%S)
      evidence="/projects/recovery/discovery-esp/swag/$stamp"
      config="$evidence/config"
      known_hosts=$(mktemp)
      printf '%s' "$HOSTKEYS" | base64 -d >"$known_hosts"
      remote_shell="sudo -H -u erik ssh -p 2222 -o BatchMode=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile=$known_hosts"
      trap 'rm -f "$known_hosts"' EXIT
      echo ":: prepare"
      sudo install -d -m 0700 -o root -g root "$config"
      echo ":: rsync"
      set +e
      sudo rsync -aHAXx --numeric-ids --delete --stats \
        --rsync-path='sudo rsync' -e "$remote_shell" \
        erik@{{ip_discovery}}:/home/erik/servarr/machines/discovery/config/swag/ "$config/"
      status=$?
      set -e
      case "$status" in 0|24) ;; *) exit "$status" ;; esac
      printf 'rsync_status=%s\n' "$status"
      for route in harbor grafana; do
        printf 'route=%s\n' "$route"
        sudo test -s "$config/nginx/proxy-confs/$route.subdomain.conf"
      done
      mapfile -t fullchains < <(sudo find -L "$config/etc/letsencrypt/live" \
        -type f -name fullchain.pem -print)
      printf 'fullchains=%s\n' "${#fullchains[@]}"
      if test "${#fullchains[@]}" = 0; then
        sudo find "$config" -maxdepth 6 \( -name fullchain.pem -o -name privkey.pem \) -print
      fi
      test "${#fullchains[@]}" -gt 0
      for fullchain in "${fullchains[@]}"; do
        privkey="$(dirname "$fullchain")/privkey.pem"
        sudo test -s "$privkey"
        sudo "$OPENSSL" x509 -checkend 604800 -noout -in "$fullchain"
        cert_key=$(sudo "$OPENSSL" x509 -in "$fullchain" -pubkey -noout |
          "$OPENSSL" pkey -pubin -outform DER | sha256sum | cut -d' ' -f1)
        private_key=$(sudo "$OPENSSL" pkey -in "$privkey" -pubout -outform DER |
          sha256sum | cut -d' ' -f1)
        test "$cert_key" = "$private_key"
      done
      sudo docker image inspect "$image" >/dev/null 2>&1 || sudo docker pull "$image"
      echo ":: nginx -t"
      sudo docker run --rm --network none --entrypoint /usr/sbin/nginx \
        -v "$config:/config" "$image" \
        -t -c /config/nginx/nginx.conf
      proxy_count=$(sudo find "$config/nginx/proxy-confs" -type f \
        -name '*.subdomain.conf' | wc -l)
      manifest=$(sudo find "$config" -xdev -printf '%P\t%y\t%s\t%m\t%U\t%G\n' |
        LC_ALL=C sort | sha256sum | cut -d' ' -f1)
      printf 'nginx=valid certificates=%s key_match=true proxy_configs=%s manifest_sha256=%s\n' \
        "${#fullchains[@]}" "$proxy_count" "$manifest" | sudo tee "$evidence/result.txt"
      sudo chmod 0600 "$evidence/result.txt"
    REMOTE
    echo ":: PASS: copied SWAG config and certificate validate on networkless Orion"

# Read-only identity/capacity/tooling gate before cloning the HAOS disk.
discovery-haos-restore-preflight:
    #!/usr/bin/env bash
    set -euo pipefail
    qemu=$(nix eval --raw .#nixosConfigurations.orion.pkgs.qemu.outPath)
    source_bytes=$(ssh -p 2222 erik@{{ip_discovery}} 'bash -s' <<'REMOTE'
      set -euo pipefail
      printf 'vault_uuid=%s vm_state=%s qemu_img=%s\n' \
        "$(findmnt -nro UUID /home/erik/vault)" \
        "$(sudo virsh domstate haos 2>/dev/null || true)" \
        "$(command -v qemu-img || true)" >&2
      sudo virsh domblklist haos --details >&2
      test "$(findmnt -nro UUID /home/erik/vault)" = d026033d-158d-49ca-9ff9-dd2d5c8a21dc
      test "$(sudo virsh domstate haos)" = running
      disk=$(sudo virsh domblklist haos --details |
        awk '$1 == "file" && $2 == "disk" { print $4 }')
      test -n "$disk"
      sudo test -f "$disk"
      bytes=$(sudo stat -c %s "$disk")
      printf 'disk=%s virtual=%s bytes=%s\n' \
        "$disk" "$(sudo qemu-img info --force-share --output json "$disk" | jq -r '."virtual-size"')" "$bytes" >&2
      printf '%s\n' "$bytes"
    REMOTE
    )
    [[ "$source_bytes" =~ ^[0-9]+$ ]]
    ssh -p 2222 erik@{{ip_orion}} \
      "SOURCE_BYTES=$source_bytes QEMU_IMG=$qemu/bin/qemu-img QEMU_SYSTEM=$qemu/bin/qemu-system-x86_64 bash -s" <<'REMOTE'
      set -euo pipefail
      printf 'qemu_img=%s qemu_system=%s projects_avail=%s\n' \
        "$([[ -x "$QEMU_IMG" ]] && echo yes || echo no)" \
        "$([[ -x "$QEMU_SYSTEM" ]] && echo yes || echo no)" \
        "$(findmnt -bnro AVAIL -T /projects 2>/dev/null || true)" >&2
      test -x "$QEMU_IMG"
      test -x "$QEMU_SYSTEM"
      available=$(findmnt -bnro AVAIL -T /projects)
      required=$((SOURCE_BYTES * 6 / 5))
      test "$available" -ge "$required"
      printf 'source_bytes=%s available=%s required=%s\n' \
        "$SOURCE_BYTES" "$available" "$required"
    REMOTE
    echo ":: PASS: HAOS disk identified and Orion has clone/boot capacity"

# Seed the HAOS QCOW2 onto Orion while the production VM remains online.
discovery-haos-restore-seed:
    #!/usr/bin/env bash
    set -euo pipefail
    just discovery-haos-restore-preflight
    scan=$(mktemp)
    trap 'rm -f "$scan"' EXIT
    ssh-keyscan -p 2222 {{ip_discovery}} >"$scan" 2>/dev/null
    ssh-keygen -lf "$scan" -E sha256 |
      grep -Fq 'SHA256:Y+aJii1TUFtxSY7+LGT0hVBzEatKss/wDHBLFFXk0HE'
    hostkeys=$(base64 -w0 "$scan")
    ssh -p 2222 erik@{{ip_orion}} "HOSTKEYS=$hostkeys bash -s" <<'REMOTE'
      set -euo pipefail
      root=/projects/recovery/discovery-esp/haos
      target=$root/haos_ova-17.1.qcow2
      known_hosts=$(mktemp)
      printf '%s' "$HOSTKEYS" | base64 -d >"$known_hosts"
      remote_shell="sudo -H -u erik ssh -p 2222 -o BatchMode=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile=$known_hosts"
      trap 'rm -f "$known_hosts"' EXIT
      sudo test ! -e "$target"
      sudo install -d -m 0700 -o root -g root "$root"
      sudo rsync -aHAXS --numeric-ids --stats \
        --rsync-path='sudo rsync' -e "$remote_shell" \
        erik@{{ip_discovery}}:/srv/vms/haos_ova-17.1.qcow2 "$target"
      sudo stat -c 'bytes=%s blocks=%b mode=%a uid=%U gid=%G' "$target"
    REMOTE
    echo ":: PASS: online HAOS clone seed complete; stopped final sync required"

# Gracefully stop HAOS, finalize its exact clone, always restart, then check clone.
discovery-haos-restore-finalize:
    #!/usr/bin/env bash
    set -euo pipefail
    qemu=$(nix eval --raw .#nixosConfigurations.orion.pkgs.qemu.outPath)
    scan=$(mktemp)
    trap 'rm -f "$scan"' EXIT
    ssh-keyscan -p 2222 {{ip_discovery}} >"$scan" 2>/dev/null
    ssh-keygen -lf "$scan" -E sha256 |
      grep -Fq 'SHA256:Y+aJii1TUFtxSY7+LGT0hVBzEatKss/wDHBLFFXk0HE'
    hostkeys=$(base64 -w0 "$scan")
    ssh -p 2222 erik@{{ip_orion}} \
      "HOSTKEYS=$hostkeys QEMU_IMG=$qemu/bin/qemu-img bash -s" <<'REMOTE'
      set -euo pipefail
      target=/projects/recovery/discovery-esp/haos/haos_ova-17.1.qcow2
      known_hosts=$(mktemp)
      printf '%s' "$HOSTKEYS" | base64 -d >"$known_hosts"
      options=(-p 2222 -o BatchMode=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile="$known_hosts")
      remote_shell="sudo -H -u erik ssh ${options[*]}"
      printf 'clone=' >&2
      sudo stat -c 'bytes=%s mode=%a' "$target" >&2 || true
      printf 'remote_vm_state=' >&2
      ssh -n "${options[@]}" erik@{{ip_discovery}} \
        'sudo virsh domstate haos 2>/dev/null || true' >&2
      sudo test -f "$target"
      resume() {
        ssh -n "${options[@]}" erik@{{ip_discovery}} \
          'sudo virsh start haos >/dev/null 2>&1 || true'
        rm -f "$known_hosts"
      }
      trap resume EXIT
      ssh -n "${options[@]}" erik@{{ip_discovery}} '
        set -euo pipefail
        test "$(findmnt -nro UUID /home/erik/vault)" = d026033d-158d-49ca-9ff9-dd2d5c8a21dc
        test "$(sudo virsh domstate haos)" = running
        sudo virsh shutdown haos
        stopped=false
        for _ in $(seq 1 300); do
          if test "$(sudo virsh domstate haos 2>/dev/null || true)" = "shut off"; then
            stopped=true
            break
          fi
          sleep 1
        done
        "$stopped"
      '
      started=$(date +%s)
      sudo rsync -aHAXS --inplace --numeric-ids --stats \
        --rsync-path='sudo rsync' -e "$remote_shell" \
        erik@{{ip_discovery}}:/srv/vms/haos_ova-17.1.qcow2 "$target"
      drift=$(sudo rsync -aHAXSni --inplace --numeric-ids \
        --rsync-path='sudo rsync' -e "$remote_shell" \
        erik@{{ip_discovery}}:/srv/vms/haos_ova-17.1.qcow2 "$target")
      test -z "$drift" || { printf '%s\n' "$drift" >&2; exit 1; }
      ssh -n "${options[@]}" erik@{{ip_discovery}} 'sudo virsh start haos'
      ssh -n "${options[@]}" erik@{{ip_discovery}} '
        set -euo pipefail
        healthy=false
        for _ in $(seq 1 180); do
          if curl --fail --silent --max-time 3 \
            http://192.168.10.115:8123/ >/dev/null 2>&1; then
            healthy=true
            break
          fi
          sleep 1
        done
        "$healthy"
        test "$(sudo virsh domstate haos)" = running
      '
      trap - EXIT
      rm -f "$known_hosts"
      sudo "$QEMU_IMG" check "$target"
      printf 'final_sync_seconds=%s drift=zero\n' "$(( $(date +%s) - started ))"
    REMOTE
    echo ":: PASS: HAOS exact clone is healthy and production VM recovered"

# Read-only completion gate after final sync/restart; never starts or stops HAOS.
discovery-haos-restore-result:
    #!/usr/bin/env bash
    set -euo pipefail
    qemu=$(nix eval --raw .#nixosConfigurations.orion.pkgs.qemu.outPath)
    ssh -p 2222 erik@{{ip_orion}} "QEMU_IMG=$qemu/bin/qemu-img bash -s" <<'REMOTE'
      set -euo pipefail
      target=/projects/recovery/discovery-esp/haos/haos_ova-17.1.qcow2
      sudo "$QEMU_IMG" check "$target"
    REMOTE
    ssh -p 2222 erik@{{ip_discovery}} 'bash -s' <<'REMOTE'
      set -euo pipefail
      test "$(sudo virsh domstate haos)" = running
      healthy=false
      for _ in $(seq 1 600); do
        if curl --fail --silent --max-time 3 \
          http://192.168.10.115:8123/ >/dev/null 2>&1; then
          healthy=true
          break
        fi
        sleep 1
      done
      "$healthy"
    REMOTE
    echo ":: PASS: HAOS clone integrity and production health recovered"

# Boot the copied HAOS disk read-only on Orion with no network device.
discovery-haos-boot-drill:
    #!/usr/bin/env bash
    set -euo pipefail
    qemu=$(nix eval --raw .#nixosConfigurations.orion.pkgs.qemu.outPath)
    ssh -p 2222 erik@{{ip_orion}} \
      "sudo QEMU=$qemu/bin/qemu-system-x86_64 FIRMWARE=$qemu/share/qemu bash -s" <<'REMOTE'
      set -euo pipefail
      disk=/projects/recovery/discovery-esp/haos/haos_ova-17.1.qcow2
      work=$(mktemp -d /projects/recovery/discovery-esp/haos/boot.XXXXXX)
      pidfile=$work/qemu.pid
      log=$work/console.log
      cleanup() {
        test ! -s "$pidfile" || kill "$(cat "$pidfile")" >/dev/null 2>&1 || true
      }
      trap cleanup EXIT
      test -x "$QEMU"
      test -f "$FIRMWARE/edk2-x86_64-code.fd"
      test -f "$FIRMWARE/edk2-i386-vars.fd"
      test -f "$disk"
      cp "$FIRMWARE/edk2-i386-vars.fd" "$work/OVMF_VARS.fd"
      "$QEMU" \
        -name discovery-haos-restore-drill \
        -machine pc,accel=kvm \
        -cpu host -m 4096 -smp 2 \
        -drive if=pflash,format=raw,readonly=on,file="$FIRMWARE/edk2-x86_64-code.fd" \
        -drive if=pflash,format=raw,file="$work/OVMF_VARS.fd" \
        -device virtio-scsi-pci,id=scsi0 \
        -drive file="$disk",format=qcow2,if=none,id=disk0 \
        -device scsi-hd,drive=disk0,bus=scsi0.0 \
        -nic none -snapshot -display none -monitor none \
        -serial file:"$log" -daemonize -pidfile "$pidfile"
      booted=false
      for _ in $(seq 1 300); do
        if grep -Eq 'Home Assistant Operating System|Welcome to Home Assistant|ha >' "$log"; then
          booted=true
          break
        fi
        test -s "$pidfile" && kill -0 "$(cat "$pidfile")"
        sleep 1
      done
      "$booted"
      grep -E 'Home Assistant Operating System|Welcome to Home Assistant|ha >' "$log" | tail -5
      kill "$(cat "$pidfile")"
      wait "$(cat "$pidfile")" 2>/dev/null || true
      trap - EXIT
      printf 'network=none disk=snapshot boot=passed\n'
    REMOTE
    echo ":: PASS: copied HAOS reached console boundary with no network"

# Read-only sample/capacity inventory before encrypted mutable-state backup.
discovery-home-restore-preflight:
    #!/usr/bin/env bash
    set -euo pipefail
    source_bytes=$(ssh -p 2222 erik@{{ip_discovery}} 'bash -s' <<'REMOTE'
      set -euo pipefail
      fixed=(
        /home/erik/.config/sops/age/keys.txt
        /etc/ssh/ssh_host_ed25519_key
      )
      for path in "${fixed[@]}" \
        /home/erik/servarr \
        /home/erik/servarr/machines/discovery/config/swag; do
        if sudo test -e "$path"; then
          printf 'exists=%s\n' "$path" >&2
        else
          printf 'missing=%s\n' "$path" >&2
        fi
      done
      for path in "${fixed[@]}"; do sudo test -s "$path"; done
      for root in \
        /home/erik/servarr \
        /home/erik/servarr/machines/discovery/config/swag; do
        sudo test -d "$root"
        sudo find "$root" -xdev -type f -size +0c -printf '%s %p\n' |
          sort -nr | sed -n '1p' >&2
      done
      sudo find /home/erik/servarr/machines/discovery/config/swag \
        -type f -name '*.pem' -printf 'pem=%p\n' | sort | tail -10 >&2
      sudo find /home/erik/Documents -xdev -type f -size +0c \
        -printf '%s %p\n' | sort -nr | sed -n '1p' >&2
      sudo find /home/erik -xdev -type f -size +1G \
        -printf '%s %p\n' | sort -nr | sed -n '1p' >&2
      bytes=$(sudo du -xsb /home/erik /etc/ssh | awk '{sum += $1} END {print sum}')
      printf 'source_bytes=%s\n' "$bytes" >&2
      printf '%s\n' "$bytes"
    REMOTE
    )
    [[ "$source_bytes" =~ ^[0-9]+$ ]]
    ssh -p 2222 erik@{{ip_kepler}} "SOURCE_BYTES=$source_bytes bash -s" <<'REMOTE'
      set -euo pipefail
      available=$(findmnt -bnro AVAIL -T /bulk)
      test "$available" -ge "$SOURCE_BYTES"
      printf 'source_bytes=%s available=%s target=/bulk/backups/discovery-esp-home\n' \
        "$SOURCE_BYTES" "$available"
    REMOTE
    echo ":: PASS: mutable-state restore classes exist and Kepler has capacity"

# Verify the new boot storage and preserved vault before state restoration.
verify-discovery-postinstall-storage:
    #!/usr/bin/env bash
    set -euo pipefail
    ssh -p 2222 erik@{{ip_discovery}} 'bash -s' <<'REMOTE'
      set -euo pipefail
      esp=$(readlink -f /dev/disk/by-id/ata-KINGSTON_SA400S37480G_AA000000000000000105-part1)
      primary=$(readlink -f /dev/disk/by-id/ata-KINGSTON_SA400S37480G_AA000000000000000105-part2)
      mirror=$(readlink -f /dev/disk/by-id/ata-KINGSTON_SA400S37480G_AA000000000000000098-part1)
      vault=$(readlink -f /dev/disk/by-id/ata-ST4000DM004-2CV104_ZTT25R4M-part1)
      for mount in /boot /home/erik/vault; do
        findmnt -nro TARGET,SOURCE,FSTYPE,UUID "$mount"
      done
      sudo btrfs filesystem show /
      sudo btrfs filesystem usage -b /
      systemctl is-active docker.service libvirtd.service openbao.service || true
      test "$(findmnt -nro SOURCE /boot)" = "$esp"
      test "$(findmnt -bnro SIZE /boot)" -ge 2000000000
      test "$(findmnt -nro FSTYPE /boot)" = vfat
      test "$(findmnt -nro UUID /home/erik/vault)" = d026033d-158d-49ca-9ff9-dd2d5c8a21dc
      test "$(findmnt -nro SOURCE /home/erik/vault)" = "$vault"
      devices=$(sudo btrfs filesystem show /)
      grep -Fq "path $primary" <<<"$devices"
      grep -Fq "path $mirror" <<<"$devices"
      sudo btrfs filesystem usage -b / | grep -Eq "^Data,RAID1:"
      sudo btrfs filesystem usage -b / | grep -Eq "^Metadata,RAID1:"
      test "$(systemctl is-active docker.service 2>/dev/null || true)" = inactive
      test "$(systemctl is-active libvirtd.service 2>/dev/null || true)" = inactive
      test "$(systemctl is-active openbao.service 2>/dev/null || true)" = inactive
    REMOTE
    echo ":: PASS: Discovery ESP, Btrfs RAID1, and vault identities verified"

# Hold stateful substrates down across dependency-triggered restarts.
quiesce-discovery-restore:
    #!/usr/bin/env bash
    set -euo pipefail
    ssh -p 2222 erik@{{ip_discovery}} 'bash -s' <<'REMOTE'
      set -euo pipefail
      units=(
        haos-vm.service
        docker.service docker.socket docker-recover.service docker-recover.timer
        libvirtd.service libvirtd.socket libvirtd-ro.socket libvirtd-admin.socket
        openbao.service openbao-unseal.service openbao-unseal.timer
        vault-agent.service
      )
      sudo systemctl mask --runtime --now "${units[@]}"
      sudo systemctl stop "${units[@]}" || true
      sudo systemctl reset-failed "${units[@]}" || true
      for unit in docker.service libvirtd.service openbao.service vault-agent.service; do
        test "$(systemctl is-active "$unit" 2>/dev/null || true)" = inactive
      done
    REMOTE
    echo ":: PASS: Discovery stateful substrates runtime-masked for restore"

# Retain a failed fresh-cluster init before retrying the pinned snapshot restore.
quarantine-discovery-openbao-throwaway:
    #!/usr/bin/env bash
    set -euo pipefail
    ssh -p 2222 erik@{{ip_discovery}} 'bash -s' <<'REMOTE'
      set -euo pipefail
      source=/var/lib/private/openbao
      retained=/var/lib/private/openbao-d5-throwaway
      if sudo test -d "$source" && sudo test ! -e "$retained"; then
        bytes=$(sudo du -sb /var/lib/private/openbao | awk '{print $1}')
        printf 'throwaway_bytes=%s state=%s\n' "$bytes" "$(systemctl is-active openbao.service 2>/dev/null || true)"
        test "$bytes" -lt 67108864
        export BAO_ADDR=http://127.0.0.1:8200
        ! BAO_TOKEN=$(sudo cat /run/secrets/vault_snapshot_token) \
          bao kv metadata get secret/shared/discord >/dev/null 2>&1
        sudo systemctl mask --runtime --now openbao.service
        sudo systemctl stop openbao.service || true
        sudo mv /var/lib/private/openbao "$retained"
      else
        sudo test -d "$retained"
        sudo test ! -e "$source"
        bytes=$(sudo du -sb "$retained" | awk '{print $1}')
      fi
      sudo install -d -m 0700 -o root -g root "$source"
      printf 'retained=%s bytes=%s\n' "$retained" "$bytes"
    REMOTE
    echo ":: PASS: failed throwaway OpenBao cluster retained; fresh state ready"

# Restore the pinned D4 OpenBao snapshot into a fresh node and prove metadata.
restore-discovery-openbao:
    #!/usr/bin/env bash
    set -euo pipefail
    RESTIC="$(nix eval --raw .#nixosConfigurations.discovery.pkgs.restic.outPath)/bin/restic"
    ssh -p 2222 erik@{{ip_discovery}} "RESTIC=$RESTIC bash -s" <<'REMOTE'
      set -euo pipefail
      snapshot=315ed0ea
      expected_sha256=8407ae773697c8511a6d2f2a24f0152dd547a91e7115148c8ecebea4f989ba29
      repository=/home/erik/vault/restic/openbao
      work=/var/lib/vault-snapshots/d5-restore-315ed0ea-v2
      sudo install -d -m 0700 -o root -g root "$work"
      test "$(findmnt -nro UUID /home/erik/vault)" = d026033d-158d-49ca-9ff9-dd2d5c8a21dc
      snap="$work/var/lib/vault-snapshots/openbao.snap"
      if ! sudo test -s "$snap"; then
        sudo env RESTIC_PASSWORD_FILE=/run/secrets/vault_restic_password \
          "$RESTIC" -r "$repository" restore "$snapshot" --target "$work"
      fi
      test "$(sudo sha256sum "$snap" | awk '{print $1}')" = "$expected_sha256"
      sudo chown -R erik:users "$work"
      chmod 0700 "$work"
      chmod 0600 "$snap"

      if ! ip link show br-openbao >/dev/null 2>&1; then
        sudo ip link add name br-openbao type bridge
      fi
      if ! ip -4 address show dev br-openbao | grep -Fq '172.31.82.1/29'; then
        sudo ip address add 172.31.82.1/29 dev br-openbao
      fi
      sudo ip link set br-openbao up
      sudo systemctl unmask --runtime openbao.service
      sudo systemctl reset-failed openbao.service
      if ! sudo systemctl start openbao.service; then
        sudo systemctl status openbao.service --no-pager -l || true
        sudo journalctl -u openbao.service -b --no-pager -n 100
        exit 1
      fi
      for _ in $(seq 1 60); do
        curl -sS -m 1 http://127.0.0.1:8200/v1/sys/health >/dev/null 2>&1 && break
        sleep 0.5
      done
      export BAO_ADDR=http://127.0.0.1:8200
      initialized=$(curl -fsS -m 10 http://127.0.0.1:8200/v1/sys/seal-status |
        jq -r '.initialized')
      if test "$initialized" = false; then
        init_json=$(bao operator init -key-shares=1 -key-threshold=1 -format=json)
        throwaway_key=$(jq -r '.unseal_keys_b64[0]' <<<"$init_json")
        throwaway_token=$(jq -r '.root_token' <<<"$init_json")
        unset init_json
        bao operator unseal "$throwaway_key" >/dev/null
        BAO_TOKEN="$throwaway_token" bao operator raft snapshot restore -force "$snap"
        unset throwaway_key throwaway_token
      fi

      echo stage=seal-status
      sealed=$(curl -fsS -m 10 http://127.0.0.1:8200/v1/sys/seal-status |
        jq -r '.sealed')
      if test "$sealed" = true; then
        unseal_key=$(sudo cat /run/secrets/vault_unseal_key)
        jq -n --arg key "$unseal_key" '{key: $key}' |
          curl -fsS -m 10 -X PUT --data @- http://127.0.0.1:8200/v1/sys/unseal >/dev/null
        unset unseal_key
      fi
      curl -fsS -m 10 http://127.0.0.1:8200/v1/sys/seal-status |
        jq -e '.initialized == true and .sealed == false' >/dev/null
      echo stage=approle-login
      role_id=$(sudo cat /run/secrets/vault_agent_role_id)
      secret_id=$(sudo cat /run/secrets/vault_agent_secret_id)
      login_json=$(jq -n --arg role_id "$role_id" --arg secret_id "$secret_id" \
        '{role_id: $role_id, secret_id: $secret_id}' |
        curl -fsS -m 10 -X POST --data @- http://127.0.0.1:8200/v1/auth/approle/login)
      unset role_id secret_id
      client_token=$(jq -er '.auth.client_token' <<<"$login_json")
      unset login_json
      echo stage=kv-proof
      BAO_TOKEN="$client_token" bao kv get -format=json secret/shared/discord |
        jq -e '.data.data | length > 0' >/dev/null
      unset client_token

      sudo systemctl unmask --runtime openbao-unseal.service openbao-unseal.timer vault-agent.service
      sudo systemctl start openbao-unseal.timer
      echo stage=vault-agent
      sudo systemctl start vault-agent.service
      for path in \
        /run/vault-agent/discord_webhook_incidents \
        /run/vault-agent/networking.env \
        /run/vault-agent/shared-db.env; do
        for _ in $(seq 1 100); do
          sudo test -s "$path" && break
          sleep 0.1
        done
        sudo test -s "$path"
      done
    REMOTE
    echo ":: PASS: OpenBao snapshot 315ed0ea restored, unsealed, and rendered"

# Restore the stopped Docker mirror, retaining the reinstall's fresh root.
restore-discovery-docker:
    #!/usr/bin/env bash
    set -euo pipefail
    evidence=.gsd/evidence/discovery-esp/manifest.json
    jq -e '
      .approval_ready == true
      and .backups.docker.cold_mirror == "/home/erik/vault/migration/discovery-docker-root"
      and .backups.docker.scratch_restore == "passed"
      and .backups.docker.metadata_sha256 == "a654304de8d8a29b1986b8ba9f2b3c19a87d58b58768b60c766d4e621ead42b5"
    ' "$evidence" >/dev/null
    evidence_sha=$(sha256sum "$evidence" | cut -d' ' -f1)
    ssh -p 2222 erik@{{ip_discovery}} "EVIDENCE_SHA=$evidence_sha bash -s" <<'REMOTE'
      set -euo pipefail
      source=/home/erik/vault/migration/discovery-docker-root
      marker=/home/erik/vault/migration/discovery-docker-root.final
      destination=/var/lib/docker
      retained=/var/lib/docker-d5-fresh
      echo stage=preflight
      vault_uuid=$(findmnt -nro UUID /home/erik/vault)
      marker_state=$(sudo test -s "$marker" && echo present || echo absent)
      source_state=$(sudo test -d "$source" && echo present || echo absent)
      printf 'vault_uuid=%s marker=%s source=%s docker=%s socket=%s\n' \
        "$vault_uuid" "$marker_state" "$source_state" \
        "$(systemctl is-active docker.service 2>/dev/null || true)" \
        "$(systemctl is-active docker.socket 2>/dev/null || true)"
      [[ "$EVIDENCE_SHA" =~ ^[0-9a-f]{64}$ ]]
      test "$vault_uuid" = d026033d-158d-49ca-9ff9-dd2d5c8a21dc
      sudo test -d "$source"
      source_bytes=$(sudo du -xsb "$source" | awk '{print $1}')
      test "$source_bytes" -gt 10737418240
      test "$(sudo find "$source/containers" -name config.v2.json -print -quit)" != ""
      docker_units=(
        docker.service docker.socket docker-recover.service docker-recover.timer
      )
      hold_units=(docker.service docker.socket)
      for unit in "${hold_units[@]}"; do
        sudo install -d -m 0755 "/run/systemd/system/$unit.d"
        printf '%s\n' \
          '[Unit]' \
          'ConditionPathExists=/run/discovery-docker-restore-start-allowed' |
          sudo tee "/run/systemd/system/$unit.d/d5-restore.conf" >/dev/null
      done
      sudo systemctl daemon-reload
      sudo systemctl mask --runtime --now "${docker_units[@]}" || true
      sudo systemctl stop "${docker_units[@]}" || true
      sudo systemctl reset-failed "${docker_units[@]}" || true
      test "$(systemctl is-active docker.service 2>/dev/null || true)" = inactive
      test "$(systemctl is-active docker.socket 2>/dev/null || true)" = inactive
      echo stage=retain
      if sudo test ! -e "$retained"; then
        fresh_bytes=$(sudo du -xsb "$destination" | awk '{print $1}')
        test "$fresh_bytes" -lt 1073741824
        sudo mv "$destination" "$retained"
      else
        sudo test -d "$retained"
      fi
      sudo install -d -m 0710 -o root -g docker "$destination"
      echo stage=rsync
      sudo rsync -aHAXx --numeric-ids --delete --stats "$source/" "$destination/"
      test "$(systemctl is-active docker.service 2>/dev/null || true)" = inactive
      test "$(systemctl is-active docker.socket 2>/dev/null || true)" = inactive
      drift=$(sudo rsync -aHAXxni --numeric-ids --delete "$source/" "$destination/")
      test -z "$drift" || { printf '%s\n' "$drift" >&2; exit 1; }
      echo stage=manifest
      source_manifest=$(sudo find "$source" -xdev ! -type d -printf '%P\t%y\t%s\t%m\t%U\t%G\n' |
        LC_ALL=C sort | sha256sum | cut -d' ' -f1)
      destination_manifest=$(sudo find "$destination" -xdev ! -type d -printf '%P\t%y\t%s\t%m\t%U\t%G\n' |
        LC_ALL=C sort | sha256sum | cut -d' ' -f1)
      expected_manifest=$source_manifest
      test "$source_manifest" = "$expected_manifest"
      test "$destination_manifest" = "$expected_manifest"
      echo stage=start
      retained_hold=/run/discovery-docker-restore-hold
      sudo install -d -m 0700 "$retained_hold"
      for unit in "${hold_units[@]}"; do
        sudo mv "/run/systemd/system/$unit.d/d5-restore.conf" \
          "$retained_hold/$unit.$$.conf"
      done
      sudo systemctl daemon-reload
      sudo systemctl unmask --runtime docker.service docker.socket
      sudo systemctl reset-failed docker.service docker.socket
      sudo systemctl start docker.service || true
      for _ in $(seq 1 300); do
        systemctl is-active --quiet docker.service && break
        sleep 1
      done
      if ! systemctl is-active --quiet docker.service; then
        sudo systemctl status docker.service docker.socket --no-pager -l || true
        sudo journalctl -u docker.service -b --no-pager -n 100
        exit 1
      fi
      test "$(sudo docker info --format '{{"{{"}}.DockerRootDir{{"}}"}}')" = /var/lib/docker
      printf 'containers=%s images=%s manifest_sha256=%s\n' \
        "$(sudo docker ps -aq | wc -l)" "$(sudo docker images -q | sort -u | wc -l)" \
        "$destination_manifest"
    REMOTE
    echo ":: PASS: Docker cold mirror restored exactly; fresh root retained"

# Resume Nix-owned stateful services after OpenBao and Docker restoration.
resume-discovery-postrestore-substrates:
    #!/usr/bin/env bash
    set -euo pipefail
    ssh -p 2222 erik@{{ip_discovery}} 'bash -s' <<'REMOTE'
      set -euo pipefail
      units=(
        docker-recover.service docker-recover.timer
        openbao-unseal.service openbao-unseal.timer
        libvirtd.service libvirtd.socket libvirtd-ro.socket libvirtd-admin.socket
        haos-vm.service
      )
      sudo systemctl unmask --runtime "${units[@]}"
      sudo systemctl reset-failed "${units[@]}" harbor.service
      sudo systemctl start docker-recover.timer openbao-unseal.timer
      sudo systemctl start docker-recover.service
      sudo systemctl start libvirtd.service
      sudo systemctl restart harbor.service
      harbor_healthy=false
      for _ in $(seq 1 180); do
        if curl -fsS -m 3 http://127.0.0.1:8085/api/v2.0/health |
          jq -e '.status == "healthy"' >/dev/null 2>&1; then
          harbor_healthy=true
          break
        fi
        sleep 1
      done
      "$harbor_healthy"
      sudo systemctl start haos-vm.service
      haos_running=false
      for _ in $(seq 1 120); do
        if sudo virsh domstate haos | grep -Fx running >/dev/null 2>&1; then
          haos_running=true
          break
        fi
        sleep 1
      done
      "$haos_running"
      systemctl is-active docker.service libvirtd.service openbao.service \
        vault-agent.service harbor.service
      BAO_ADDR=http://127.0.0.1:8200 bao status | grep -Eq '^Sealed[[:space:]]+false$'
      sudo virsh domstate haos | grep -Fx running
    REMOTE
    echo ":: PASS: Docker recovery, unseal, Harbor, libvirt, and HAOS resumed"

# Read-only live AdGuard identity/mount/capacity gate for isolated restore.
discovery-adguard-restore-preflight:
    #!/usr/bin/env bash
    set -euo pipefail
    source_bytes=$(ssh -p 2222 erik@{{ip_discovery}} 'bash -s' <<'REMOTE'
      set -euo pipefail
      expected='adguard/adguardhome:v0.108.0-b.83@sha256:8399ec9bdcb76d5ef4f217ed2d0272dc9f3fb283eb2613744610988232d91927'
      inspect=$(sudo docker inspect adguard)
      jq -c '.[0] | {
        status: .State.Status,
        image: .Config.Image,
        mounts: [.Mounts[] | {type: .Type, name: .Name, source: .Source, destination: .Destination}]
      }' <<<"$inspect" >&2
      test "$(jq -r '.[0].State.Status' <<<"$inspect")" = running
      test "$(jq -r '.[0].Config.Image' <<<"$inspect")" = "$expected"
      work=$(jq -r '.[0].Mounts[] | select(.Destination == "/opt/adguardhome/work") | .Source' <<<"$inspect")
      config=$(jq -r '.[0].Mounts[] | select(.Destination == "/opt/adguardhome/conf") | .Source' <<<"$inspect")
      sudo test -d "$work"
      sudo test -d "$config"
      work_bytes=$(sudo du -xsb "$work" | cut -f1)
      config_bytes=$(sudo du -xsb "$config" | cut -f1)
      printf 'work=%s bytes=%s config=%s bytes=%s\n' \
        "$work" "$work_bytes" "$config" "$config_bytes" >&2
      jq -c '.[0] | {
        image: .Config.Image,
        mounts: [.Mounts[] | {type: .Type, source: .Source, destination: .Destination}],
        ports: .NetworkSettings.Ports
      }' <<<"$inspect" >&2
      printf '%s\n' "$((work_bytes + config_bytes))"
    REMOTE
    )
    [[ "$source_bytes" =~ ^[0-9]+$ ]]
    ssh -p 2222 erik@{{ip_orion}} "SOURCE_BYTES=$source_bytes bash -s" <<'REMOTE'
      set -euo pipefail
      available=$(findmnt -bnro AVAIL -T /projects)
      required=$((SOURCE_BYTES * 2))
      test "$available" -ge "$required"
      printf 'source_bytes=%s available=%s required=%s\n' \
        "$SOURCE_BYTES" "$available" "$required"
    REMOTE
    echo ":: PASS: live AdGuard state identified and Orion has restore capacity"

# Seed live AdGuard volume/config state onto Orion; stopped final sync follows.
discovery-adguard-restore-seed:
    #!/usr/bin/env bash
    set -euo pipefail
    just discovery-adguard-restore-preflight
    scan=$(mktemp)
    trap 'rm -f "$scan"' EXIT
    ssh-keyscan -p 2222 {{ip_discovery}} >"$scan" 2>/dev/null
    ssh-keygen -lf "$scan" -E sha256 |
      grep -Fq 'SHA256:Y+aJii1TUFtxSY7+LGT0hVBzEatKss/wDHBLFFXk0HE'
    hostkeys=$(base64 -w0 "$scan")
    ssh -p 2222 erik@{{ip_orion}} "sudo HOSTKEYS=$hostkeys bash -s" <<'REMOTE'
      set -euo pipefail
      root=/projects/recovery/discovery-esp/adguard
      known_hosts=$(mktemp)
      printf '%s' "$HOSTKEYS" | base64 -d >"$known_hosts"
      chmod 0644 "$known_hosts"
      remote_shell="sudo -H -u erik ssh -p 2222 -o BatchMode=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile=$known_hosts"
      trap 'rm -f "$known_hosts"' EXIT
      install -d -m 0700 "$root/work" "$root/conf"
      rsync -aHAXx --numeric-ids --delete --stats \
        --rsync-path='sudo rsync' -e "$remote_shell" \
        erik@{{ip_discovery}}:/var/lib/docker/volumes/discovery-adguard-work/_data/ "$root/work/"
      rsync -aHAXx --numeric-ids --delete --stats \
        --rsync-path='sudo rsync' -e "$remote_shell" \
        erik@{{ip_discovery}}:/home/erik/servarr/machines/discovery/runtime/adguard/ "$root/conf/"
      du -xsb "$root/work" "$root/conf"
    REMOTE
    echo ":: PASS: online AdGuard restore seed complete; stopped final sync required"

# Stop only AdGuard and its exporter for the final delta, then restore both.
discovery-adguard-restore-finalize:
    #!/usr/bin/env bash
    set -euo pipefail
    discovery={{ip_discovery}}
    kepler={{ip_kepler}}
    evidence=.gsd/evidence/p3-dns/runs/20260715T235959Z-d5cf3b5979d8/result.json
    jq -e '.status == "passed"' "$evidence" >/dev/null
    for transport in +notcp +tcp; do
      test "$(dig "$transport" +short +time=3 +tries=1 @"$kepler" \
        discovery.homelab.pastelariadev.com A)" = "$discovery"
      test -n "$(dig "$transport" +short +time=3 +tries=1 @"$kepler" example.com A)"
    done
    inspect=$(ssh -p 2222 erik@"$discovery" \
      'sudo docker inspect adguard adguard-exporter')
    adguard_id=$(jq -r '.[] | select(.Name == "/adguard") | .Id' <<<"$inspect")
    exporter_id=$(jq -r '.[] | select(.Name == "/adguard-exporter") | .Id' <<<"$inspect")
    [[ "$adguard_id" =~ ^[0-9a-f]{64}$ && "$exporter_id" =~ ^[0-9a-f]{64}$ ]]
    test "$(jq -r '[.[].State.Running] | all' <<<"$inspect")" = true
    scan=$(mktemp)
    trap 'rm -f "$scan"' EXIT
    ssh-keyscan -p 2222 "$discovery" >"$scan" 2>/dev/null
    ssh-keygen -lf "$scan" -E sha256 |
      grep -Fq 'SHA256:Y+aJii1TUFtxSY7+LGT0hVBzEatKss/wDHBLFFXk0HE'
    hostkeys=$(base64 -w0 "$scan")
    stopped=1
    restart() {
      if test "$stopped" = 1; then
        ssh -p 2222 erik@"$discovery" \
          sudo docker start "$adguard_id" "$exporter_id" >/dev/null
        stopped=0
      fi
    }
    trap restart EXIT INT TERM
    started=$(date +%s)
    ssh -p 2222 erik@"$discovery" \
      sudo docker stop --time 120 "$exporter_id" "$adguard_id" >/dev/null
    ssh -p 2222 erik@{{ip_orion}} "sudo HOSTKEYS=$hostkeys bash -s" <<'REMOTE'
      set -euo pipefail
      root=/projects/recovery/discovery-esp/adguard
      test -d "$root/work" -a -d "$root/conf"
      known_hosts=$(mktemp)
      printf '%s' "$HOSTKEYS" | base64 -d >"$known_hosts"
      chmod 0644 "$known_hosts"
      trap 'rm -f "$known_hosts"' EXIT
      remote_shell="sudo -H -u erik ssh -p 2222 -o BatchMode=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile=$known_hosts"
      sync() {
        rsync -aHAXx --numeric-ids --delete "$@" \
          --rsync-path='sudo rsync' -e "$remote_shell"
      }
      sync erik@{{ip_discovery}}:/var/lib/docker/volumes/discovery-adguard-work/_data/ "$root/work/"
      sync erik@{{ip_discovery}}:/home/erik/servarr/machines/discovery/runtime/adguard/ "$root/conf/"
      work_drift=$(sync --dry-run --itemize-changes \
        erik@{{ip_discovery}}:/var/lib/docker/volumes/discovery-adguard-work/_data/ "$root/work/")
      conf_drift=$(sync --dry-run --itemize-changes \
        erik@{{ip_discovery}}:/home/erik/servarr/machines/discovery/runtime/adguard/ "$root/conf/")
      test -z "$work_drift$conf_drift"
      du -xsb "$root/work" "$root/conf"
    REMOTE
    restart
    trap - EXIT INT TERM
    dns_ready=false
    for _ in $(seq 1 60); do
      running=$(ssh -p 2222 erik@"$discovery" \
        "sudo docker inspect '$adguard_id' '$exporter_id'" |
        jq -r '[.[].State.Running] | all')
      if test "$running" = true; then
        dns_ready=true
        for transport in +notcp +tcp; do
          test "$(dig "$transport" +short +time=3 +tries=1 @"$discovery" \
            discovery.homelab.pastelariadev.com A)" = "$discovery" ||
            dns_ready=false
          test -n "$(dig "$transport" +short +time=3 +tries=1 \
            @"$discovery" example.com A)" ||
            dns_ready=false
        done
        test "$dns_ready" = true && break
      fi
      sleep 1
    done
    test "$dns_ready" = true
    echo ":: PASS: stopped AdGuard final sync complete; downtime=$(( $(date +%s) - started ))s"

# Boot a disposable copy of AdGuard on Orion loopback and prove DNS behavior.
discovery-adguard-restore-drill:
    #!/usr/bin/env bash
    set -euo pipefail
    ssh -p 2222 erik@{{ip_orion}} 'sudo bash -s' <<'REMOTE'
      set -euo pipefail
      image='adguard/adguardhome:v0.108.0-b.83@sha256:8399ec9bdcb76d5ef4f217ed2d0272dc9f3fb283eb2613744610988232d91927'
      root=/projects/recovery/discovery-esp/adguard
      source_work=/projects/recovery/discovery-esp/adguard/work
      source_conf=/projects/recovery/discovery-esp/adguard/conf
      run=$root/runs/$(date -u +%Y%m%dT%H%M%SZ)
      work=$run/work
      conf=$run/conf
      name=discovery-adguard-restore-drill
      command -v dig >/dev/null
      test -d "$source_work" -a -d "$source_conf"
      ! docker inspect "$name" >/dev/null 2>&1
      ! ss -H -lntu | grep -Eq '127\.0\.0\.1:(15353|18090)[[:space:]]'
      install -d -m 0700 "$work" "$conf"
      cp -a --reflink=auto "$source_work/." "$work/"
      cp -a --reflink=auto "$source_conf/." "$conf/"
      docker image inspect "$image" >/dev/null 2>&1 || docker pull "$image"
      created=false
      cleanup() {
        if "$created"; then
          docker stop --time 30 "$name" >/dev/null 2>&1 || true
        fi
      }
      trap cleanup EXIT INT TERM
      docker run --detach --rm --name "$name" \
        -p 127.0.0.1:15353:53/tcp \
        -p 127.0.0.1:15353:53/udp \
        -p 127.0.0.1:18090:80/tcp \
        -v "$work:/opt/adguardhome/work" \
        -v "$conf:/opt/adguardhome/conf" \
        "$image" >/dev/null
      created=true
      dns_ready=false
      for _ in $(seq 1 60); do
        if test "$(dig +notcp +short +time=2 +tries=1 -p 15353 \
          @127.0.0.1 restore-drill.homelab.pastelariadev.com A)" = \
          192.168.10.210; then
          dns_ready=true
          break
        fi
        sleep 1
      done
      test "$dns_ready" = true
      for transport in +notcp +tcp; do
        test "$(dig "$transport" +short +time=3 +tries=1 -p 15353 \
          @127.0.0.1 restore-drill.homelab.pastelariadev.com A)" = \
          192.168.10.210
        test -n "$(dig "$transport" +short +time=3 +tries=1 -p 15353 \
          @127.0.0.1 example.com A)"
        test "$(dig "$transport" +short +time=3 +tries=1 -p 15353 \
          @127.0.0.1 restore-drill.doubleclick.net A)" = 0.0.0.0
        dig "$transport" +dnssec +time=3 +tries=1 -p 15353 \
          @127.0.0.1 cloudflare.com A |
          grep -Eq 'flags:.* ad[;[:space:]]'
      done
      curl --fail --silent --show-error --max-time 3 \
        -o /dev/null http://127.0.0.1:18090/
      docker inspect "$name" |
        jq -c '.[0] | {
          image: .Image,
          running: .State.Running,
          ports: .NetworkSettings.Ports,
          mounts: [.Mounts[] | {source: .Source, destination: .Destination}]
        }' | tee "$run/result.json"
      test "$(jq -r .running "$run/result.json")" = true
      echo ":: PASS: isolated AdGuard restore resolves fleet/external/filter/DNSSEC over UDP+TCP"
    REMOTE

# Read-only post-install acceptance gate. Run only after dependency-ordered
# restoration has completed; it does not start or repair any service.
diagnose-discovery-gpu:
    #!/usr/bin/env bash
    set -euo pipefail
    pciutils="$(nix eval --raw .#nixosConfigurations.discovery.pkgs.pciutils.outPath)"
    ssh -p 2222 erik@{{ip_discovery}} "TOOLS_PATH=$pciutils/bin bash -s" <<'REMOTE'
      export PATH="$TOOLS_PATH:$PATH"
      echo ":: pci"
      lspci -nnk | grep -A3 -Ei 'VGA|3D|NVIDIA' || true
      echo ":: modules"
      lsmod | grep -E '^nvidia' || true
      echo ":: devices"
      for device in /dev/nvidia*; do
        test ! -e "$device" || stat -c '%n %a %U:%G' "$device"
      done
      echo ":: nvidia-smi"
      nvidia-smi || true
      echo ":: units"
      systemctl status nvidia-persistenced.service \
        nvidia-container-toolkit-cdi-generator.service --no-pager -l || true
      echo ":: kernel"
      journalctl -b -k --no-pager |
        grep -Ei 'nvidia|nouveau|NVRM|BAR|IOMMU|firmware' | tail -120 || true
    REMOTE

# Run one bounded 4K60 NVENC load and sample fan/thermal telemetry.
test-discovery-gpu-load duration="60":
    #!/usr/bin/env bash
    set -euo pipefail
    duration={{duration}}
    test "$duration" -ge 5
    test "$duration" -le 900
    ssh -p 2222 erik@{{ip_discovery}} "DURATION=$duration bash -s" <<'REMOTE'
      set -euo pipefail
      duration=$DURATION
      query() {
        nvidia-smi --query-gpu=timestamp,fan.speed,temperature.gpu,power.draw,utilization.gpu,utilization.encoder \
          --format=csv,noheader
      }
      image=lscr.io/linuxserver/jellyfin:10.11.11@sha256:bb8d372e35d5c4a6cb61d830a06f5b5846528315b97cf5d38b80eea1e430efa7
      sudo docker inspect -f '{{"{{"}}.State.Health.Status{{"}}"}}' jellyfin | grep -Fx healthy
      sudo docker image inspect "$image" >/dev/null
      query
      timeout "$((duration + 20))" sudo docker run --rm --pull never \
        --network none --device nvidia.com/gpu=all \
        --entrypoint /usr/lib/jellyfin-ffmpeg/ffmpeg "$image" \
        -hide_banner -loglevel error -re \
        -f lavfi -i testsrc2=size=3840x2160:rate=60 -t "$duration" \
        -c:v h264_nvenc -preset p1 -f null - &
      load_pid=$!
      for _ in $(seq 1 "$((duration / 2 + 2))"); do
        query
        kill -0 "$load_pid" 2>/dev/null || break
        sleep 2
      done
      wait "$load_pid"
      query
    REMOTE

# Temporarily request a fixed GPU fan speed through a private headless X server.
test-discovery-gpu-fan percent="80" duration="10":
    #!/usr/bin/env bash
    set -euo pipefail
    percent={{percent}}
    duration={{duration}}
    test "$percent" -ge 30
    test "$percent" -le 100
    test "$duration" -ge 5
    test "$duration" -le 30
    xorg=$(nix eval --raw .#nixosConfigurations.discovery.pkgs.xorg.xorgserver.outPath)
    settings=$(nix eval --raw .#nixosConfigurations.discovery.config.hardware.nvidia.package.settings.outPath)
    driver=$(nix eval --raw .#nixosConfigurations.discovery.config.hardware.nvidia.package.bin.outPath)
    nix-store --realise "$xorg" "$settings" "$driver" >/dev/null
    nix copy --to ssh-ng://erik@{{ip_discovery}}:2222 "$xorg" "$settings" "$driver"
    ssh -p 2222 erik@{{ip_discovery}} \
      "sudo bash -s -- $xorg $settings $driver $percent $duration" <<'REMOTE'
      set -euo pipefail
      xorg=$1
      settings=$2
      driver=$3
      percent=$4
      duration=$5
      work=$(mktemp -d /run/discovery-gpu-fan-test.XXXXXX)
      printf '%s\n' \
        'Section "Files"' \
        "  ModulePath \"$driver/lib/xorg/modules\"" \
        "  ModulePath \"$xorg/lib/xorg/modules\"" \
        'EndSection' \
        'Section "Device"' \
        '  Identifier "GPU0"' \
        '  Driver "nvidia"' \
        '  BusID "PCI:1:0:0"' \
        '  Option "Coolbits" "4"' \
        '  Option "AllowEmptyInitialConfiguration" "True"' \
        'EndSection' \
        'Section "Screen"' \
        '  Identifier "Screen0"' \
        '  Device "GPU0"' \
        'EndSection' >"$work/xorg.conf"
      "$xorg/bin/Xorg" :99 -config "$work/xorg.conf" -noreset -nolisten tcp \
        -logfile "$work/Xorg.log" >"$work/stdout.log" 2>&1 &
      xpid=$!
      cleanup() {
        "$settings/bin/nvidia-settings" -c :99 \
          -a '[gpu:0]/GPUFanControlState=0' || true
        kill "$xpid" 2>/dev/null || true
        wait "$xpid" 2>/dev/null || true
      }
      trap cleanup EXIT
      for _ in $(seq 1 10); do
        "$settings/bin/nvidia-settings" -c :99 -q gpus >/dev/null 2>&1 && break
        kill -0 "$xpid" 2>/dev/null || {
          cat "$work/Xorg.log"
          exit 1
        }
        sleep 1
      done
      "$settings/bin/nvidia-settings" -c :99 -q gpus >/dev/null
      nvidia-smi --query-gpu=fan.speed,temperature.gpu,power.draw --format=csv,noheader
      "$settings/bin/nvidia-settings" -c :99 \
        -a '[gpu:0]/GPUFanControlState=1' \
        -a "[fan:0]/GPUTargetFanSpeed=$percent"
      sleep "$duration"
      "$settings/bin/nvidia-settings" -c :99 \
        -q '[fan:0]/GPUCurrentFanSpeed' \
        -q '[fan:0]/GPUTargetFanSpeed'
      nvidia-smi --query-gpu=fan.speed,temperature.gpu,power.draw --format=csv,noheader
    REMOTE

# Read-only post-install acceptance gate. Run only after dependency-ordered
# restoration has completed; it does not start or repair any service.
verify-discovery-esp:
    #!/usr/bin/env bash
    set -euo pipefail
    ssh -p 2222 erik@{{ip_discovery}} 'bash -s' <<'REMOTE'
      set -euo pipefail
      esp_bytes=$(findmnt -bnro SIZE /boot)
      test "$esp_bytes" -ge 2000000000
      test "$(findmnt -nro FSTYPE /boot)" = vfat
      test "$(findmnt -nro UUID /home/erik/vault)" = d026033d-158d-49ca-9ff9-dd2d5c8a21dc
      test "$(sudo docker info --format '{{"{{"}}.DockerRootDir{{"}}"}}')" = /var/lib/docker
      sudo btrfs filesystem usage -b / | grep -Eq '^Data,RAID1:'
      sudo btrfs filesystem usage -b / | grep -Eq '^Metadata,RAID1:'
      sudo systemctl is-active sshd tailscaled docker libvirtd openbao vault-agent openbao-unseal.timer
      test "$(systemctl show -p Result --value openbao-unseal.service)" = success
      echo stage=openbao
      BAO_ADDR=http://127.0.0.1:8200 bao status | grep -Eq '^Sealed[[:space:]]+false$'
      echo stage=dns
      dig +short +time=3 +tries=1 @{{ip_discovery}} discovery.homelab.pastelariadev.com A | grep -Eq '^[0-9]+(\.[0-9]+){3}$'
      echo stage=grafana
      curl -kfsS -o /dev/null https://grafana.homelab.pastelariadev.com/
      echo stage=haos
      sudo virsh domstate haos | grep -Fx running
      echo stage=failed-units
      failed=$(systemctl --failed --no-legend | awk 'NF')
      printf '%s' "$failed"
      test -z "$failed"
      printf 'generation='; readlink -f /run/current-system
      printf 'esp_bytes=%s\n' "$esp_bytes"
      sudo docker ps --format '{{"{{"}}.Names{{"}}"}}\t{{"{{"}}.Status{{"}}"}}' | sort
    REMOTE
    echo ":: PASS: Discovery post-install critical acceptance gate"

# Value-free service/generation evidence after a Discovery activation failure.
discovery-activation-diagnostic:
    #!/usr/bin/env bash
    set -euo pipefail
    ssh -p 2222 -o BatchMode=yes erik@{{ip_discovery}} 'bash -s' <<'REMOTE'
    set -euo pipefail
    readlink -f /run/current-system /nix/var/nix/profiles/system
    systemctl list-jobs --no-pager
    for unit in docker-hermes-agent docker-hermes-argus docker-hermes-daedalus hermes-wiki-cron-seed openbao; do
      systemctl show "$unit" -p Id -p ActiveState -p SubState -p Result
      pid=$(systemctl show "$unit" -p MainPID --value)
      if [ "$pid" != 0 ]; then ps -p "$pid" -o pid,comm,wchan:32; fi
    done
    timeout 15 sudo docker ps -a --format "{{"{{"}}.Names{{"}}"}} {{"{{"}}.Status{{"}}"}}" || true
    timeout 15 sudo docker image ls --format "{{"{{"}}.Repository{{"}}"}} {{"{{"}}.ID{{"}}"}}" | grep hermes || true
    df -h /var/lib/docker /nix /home
    REMOTE
