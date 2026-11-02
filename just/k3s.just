# Fetch cp-1's admin kubeconfig → repoint at the LB admin endpoint (via discovery)
# → rename context to 'homelab' → ~/.kube/config. Run after a fresh laptop
# or a cluster reform. cp-1 (clusterInit server, 10.250.0.11) is on the private
# subnet, reached by agent-forward (kepler sshd disallows TCP forwarding).
kubeconfig:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p ~/.kube
    tmp=$(mktemp ~/.kube/config.XXXXXX)
    trap 'rm -f "$tmp"' EXIT
    ssh -A -o StrictHostKeyChecking=accept-new -p 2222 erik@{{ip_kepler}} \
        'ssh -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null root@10.250.0.11 "cat /etc/rancher/k3s/k3s.yaml"' \
        | sed 's#https://127.0.0.1:6443#https://k8s.pastelariadev.com:6443#' \
        | sed 's/: default$/: homelab/' \
        > "$tmp"
    chmod 600 "$tmp"
    mv "$tmp" ~/.kube/config
    trap - EXIT
    echo ":: kubeconfig → context $(kubectl config current-context)"
    kubectl get nodes

# LAN-direct kubeconfig → apiserver VIP 192.168.10.245 (cert SAN covers it),
# bypassing discovery's stream-proxy. Use on the kepler LAN or when discovery is
# down (grill §5 — admin access must not depend on a second host). Separate file;
# use via `KUBECONFIG=~/.kube/homelab-lan.yaml kubectl …`.
kubeconfig-lan:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p ~/.kube
    tmp=$(mktemp ~/.kube/homelab-lan.yaml.XXXXXX)
    trap 'rm -f "$tmp"' EXIT
    ssh -A -o StrictHostKeyChecking=accept-new -p 2222 erik@{{ip_kepler}} \
        'ssh -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null root@10.250.0.11 "cat /etc/rancher/k3s/k3s.yaml"' \
        | sed 's#https://127.0.0.1:6443#https://192.168.10.245:6443#' \
        | sed 's/: default$/: homelab-lan/' \
        > "$tmp"
    chmod 600 "$tmp"
    mv "$tmp" ~/.kube/homelab-lan.yaml
    trap - EXIT
    echo ":: LAN kubeconfig → ~/.kube/homelab-lan.yaml (context homelab-lan)"
    KUBECONFIG=~/.kube/homelab-lan.yaml kubectl get nodes

# After pulling, kick the compose stack on the remote host:
#   just kick-stack kepler ai-serving
kick-stack target stack:
    #!/usr/bin/env bash
    set -euo pipefail
    IP="$(just _host-ip {{target}})"
    # restart (not start): the unit is RemainAfterExit, so `start` no-ops once
    # active and would not re-run `compose up -d --remove-orphans`.
    ssh -p 2222 erik@$IP 'uid=$(id -u); sudo systemctl start user-runtime-dir@$uid.service user@$uid.service; export XDG_RUNTIME_DIR=/run/user/$uid; systemctl --user restart podman-compose-{{stack}}.service'
    ssh -p 2222 erik@$IP 'export XDG_RUNTIME_DIR=/run/user/$(id -u); systemctl --user status podman-compose-{{stack}}.service --no-pager -n10'

# Live proof for Orion's Kubernetes-backed Wazuh canary.
verify-wazuh-agent-canary:
    #!/usr/bin/env bash
    set -euo pipefail
    ssh -p 2222 erik@{{ip_orion}} 'set -euo pipefail
      systemctl is-active wazuh-agent-vault.service podman-wazuh-agent.service syslog.service
      sudo podman inspect wazuh-agent | jq -e '\''.[0].State.Status == "running"'\'' >/dev/null'
    echo ":: Manager enrollment"
    kubectl --context homelab -n wazuh exec statefulset/wazuh-manager-master -c wazuh-manager -- \
      sh -c '/var/ossec/bin/agent_control -lc | grep -F orion-canary >/dev/null'
    echo ":: Attributed host SSH alert"
    kubectl --context homelab -n wazuh exec statefulset/wazuh-manager-worker -c wazuh-manager -- \
      tail -n 10000 /var/ossec/logs/alerts/alerts.json | \
      jq -R -e 'fromjson? | select(.agent.name == "orion-canary" and .location == "/var/log/wazuh-host/sshd.log" and ((.rule.groups // []) | index("sshd"))) | true' >/dev/null
    echo ":: Orion Wazuh canary enrolled and host SSH alerts present"

probe-wazuh-agent-canary:
    #!/usr/bin/env bash
    set -euo pipefail
    marker="wazuh-$(cat /proc/sys/kernel/random/uuid)"
    ssh -p 2222 -o BatchMode=yes erik@{{ip_orion}} "bash -s -- $marker" <<'REMOTE'
    set -euo pipefail
    marker=$1
    ! getent passwd "$marker" >/dev/null
    known_hosts=$(mktemp)
    trap 'rm -f -- "$known_hosts"' EXIT
    awk '{print "[127.0.0.1]:2222 " $1 " " $2}' /etc/ssh/ssh_host_ed25519_key.pub >"$known_hosts"
    since=$(date --iso-8601=seconds)
    excluded="wazuh-excluded-$(cat /proc/sys/kernel/random/uuid)"
    sudo systemd-run --quiet --wait --collect --unit="$excluded" \
      --property=SyslogIdentifier=sshd-session --property=StandardOutput=journal \
      /run/current-system/sw/bin/printf '%s\n' \
      "Failed password for invalid user $excluded from 192.0.2.1 port 4242 ssh2"
    sudo journalctl --sync
    sudo journalctl -u "$excluded.service" --since "$since" --no-pager -o cat | grep -F "$excluded" >/dev/null
    status=0
    ssh -F /dev/null -p 2222 -o BatchMode=yes -o ConnectTimeout=5 \
      -o ConnectionAttempts=1 -o PreferredAuthentications=none \
      -o StrictHostKeyChecking=yes -o UserKnownHostsFile="$known_hosts" \
      -o GlobalKnownHostsFile=/dev/null -o HostKeyAlgorithms=ssh-ed25519 \
      "$marker@127.0.0.1" true >/dev/null 2>&1 || status=$?
    test "$status" -eq 255
    sudo journalctl --sync
    sudo journalctl -u sshd.service --since "$since" --no-pager -o cat | grep -F "$marker" >/dev/null
    seen=false
    for _ in {1..30}; do
      status=0
      sudo grep -F "$marker" /var/log/wazuh-host/sshd.log >/dev/null || status=$?
      if [ "$status" -eq 0 ]; then seen=true; break; fi
      test "$status" -eq 1
      sleep 2
    done
    "$seen"
    status=0
    sudo grep -F "$excluded" /var/log/wazuh-host/sshd.log >/dev/null || status=$?
    test "$status" -eq 1
    REMOTE
    seen=false
    for _ in {1..30}; do
      if kubectl --context homelab -n wazuh exec statefulset/wazuh-manager-worker -c wazuh-manager -- \
        tail -n 10000 /var/ossec/logs/alerts/alerts.json | \
        jq -R -e --arg marker "$marker" 'fromjson? | select(.agent.name == "orion-canary" and .location == "/var/log/wazuh-host/sshd.log" and ((.rule.groups // []) | index("sshd")) and ((.full_log // "") | contains($marker))) | true' >/dev/null; then
        seen=true
        break
      fi
      sleep 2
    done
    "$seen"
    just verify-wazuh-agent-canary

stop-k3s-worker target:
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{target}}" in
      w-1|w-2|w-3) ;;
      *) echo "invalid worker: {{target}}" >&2; exit 2 ;;
    esac
    uncordon_on_failure() {
      exit_code=$?
      trap - EXIT
      if (( exit_code != 0 )); then
        kubectl --context homelab uncordon "{{target}}" >/dev/null 2>&1 || true
      fi
      exit "$exit_code"
    }
    trap uncordon_on_failure EXIT
    kubectl --context homelab drain "{{target}}" \
      --ignore-daemonsets --delete-emptydir-data --timeout=5m
    ssh -p 2222 erik@{{ip_kepler}} 'sudo systemctl stop microvm@{{target}}.service
      state=$(sudo systemctl is-active microvm@{{target}}.service || true)
      test "$state" = inactive'
    trap - EXIT

restart-k3s-worker target:
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{target}}" in
      w-1|w-2|w-3) ;;
      *) echo "invalid worker: {{target}}" >&2; exit 2 ;;
    esac
    ssh -p 2222 erik@{{ip_kepler}} "sudo systemctl restart microvm@{{target}}.service"
    kubectl --context homelab wait --for=condition=Ready node/{{target}} --timeout=5m
    kubectl --context homelab uncordon {{target}}

# Read-only proof for the k3s guest reconciler and embedded-etcd metrics.
verify-k3s-observability:
    #!/usr/bin/env bash
    set -euo pipefail
    ssh -p 2222 erik@{{ip_kepler}} '
      set -euo pipefail
      for attempt in $(seq 1 60); do
        states=$(sudo systemctl is-active microvm@cp-1.service microvm@cp-2.service microvm@cp-3.service || true)
        if [ "$(printf '%s\n' "$states" | grep -c '^active$')" -eq 3 ]; then
          break
        fi
        if [ "$attempt" -eq 60 ]; then
          printf '%s\n' "$states" >&2
          exit 1
        fi
        sleep 5
      done
      for node in 11 12 13; do
        ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null root@10.250.0.$node \
          "systemctl is-active k3s.service k3s-manifest-reconcile.service"
        curl --fail --silent --show-error --max-time 5 http://10.250.0.$node:2381/metrics \
          | grep -c "^etcd_server_has_leader 1$" | grep -qx 1
      done
    '
    response=$(kubectl --context homelab -n monitoring exec \
      statefulset/prometheus-monitoring-kube-prometheus-prometheus -c prometheus -- \
      wget -qO- 'http://127.0.0.1:9090/api/v1/query?query=up%7Bjob%3D%22etcd%22%7D')
    printf '%s\n' "$response" | jq -c '.data.result[]? | {instance: .metric.instance, value: .value[1]}'
    test "$(printf '%s\n' "$response" | jq '[.data.result[]? | select(.value[1] == "1")] | length')" -eq 3

# Grow existing k3s root images to the sizes declared in k3s-cluster.nix.
# Offline + grow-only: shrinking or an unexpected filesystem aborts.
resize-kepler-k3s-disks:
    #!/usr/bin/env bash
    set -euo pipefail
    ssh -p 2222 erik@{{ip_kepler}} 'sudo bash -s' <<'REMOTE'
      set -euo pipefail
      declare -A sizes=(
        [cp-1]=32768 [cp-2]=32768 [cp-3]=32768
        [w-1]=131072 [w-2]=131072
      )
      names=(cp-1 cp-2 cp-3 w-1 w-2)
      systemctl stop microvms.target "${names[@]/#/microvm@}"
      trap 'systemctl start microvms.target' EXIT
      for name in "${names[@]}"; do
        image="/fast/microvms/$name/root.img"
        test -f "$image"
        file -s "$image" | grep -q 'ext4 filesystem'
        current=$(stat -c %s "$image")
        wanted=$((sizes[$name] * 1024 * 1024))
        (( current > wanted )) && {
          echo "refusing to shrink $name: $current > $wanted" >&2
          exit 1
        }
        if (( current < wanted )); then
          truncate -s "$wanted" "$image"
        fi
        e2fsck -fp "$image" || [ "$?" -eq 1 ]
        resize2fs "$image"
      done
      trap - EXIT
      systemctl start microvms.target
    REMOTE

# Read-only proof that cp-1's timer last reconciled both bootstrap Secrets.
verify-k3s-bootstrap:
    #!/usr/bin/env bash
    set -euo pipefail
    ssh -p 2222 erik@{{ip_kepler}} '
      set -euo pipefail
      ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null root@10.250.0.11 '\''
        set -euo pipefail
        systemctl is-active k3s-bootstrap-secrets.timer
        test "$(systemctl show k3s-bootstrap-secrets.service -p Result --value)" = success
        k3s kubectl -n argocd get secret homelab-gitops-repo -o name
        k3s kubectl -n external-secrets get secret vault-approle -o name
        k3s kubectl wait --for=condition=Ready clustersecretstore/vault-discovery --timeout=2m
      '\''
    '

# Read-only startup detail for k3s microVMs and their virtiofs helpers.
diagnose-k3s-guests:
    ssh -p 2222 erik@{{ip_kepler}} "sudo systemctl list-jobs --no-pager; sudo systemctl status microvms.target k3s-bootstrap-materialize.service microvm@cp-{1,2,3}.service --no-pager -l; sudo journalctl -b -u k3s-bootstrap-materialize.service -u microvm@cp-1.service -u install-microvm-cp-1.service --no-pager -n 120; sudo find -L /run/secrets -maxdepth 2 -printf 'secret-path %P %y\n'; sudo find /run/k3s-bootstrap -maxdepth 1 -type f -printf 'host %f %s bytes\n'; ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null root@10.250.0.11 'find /run/k3s-bootstrap -maxdepth 1 -type f -printf \"guest %f %s bytes\\n\"; systemctl status k3s.service k3s-bootstrap-secrets.service k3s-bootstrap-secrets.timer --no-pager -l; journalctl -b -u k3s.service -u k3s-bootstrap-secrets.service --no-pager -n 120'"

# Retry the exact bootstrap dependency chain after a diagnosed boot failure.
recover-k3s-bootstrap-guest:
    ssh -p 2222 erik@{{ip_kepler}} "sudo systemctl reset-failed k3s-bootstrap-materialize.service microvm@cp-1.service; sudo systemctl start k3s-bootstrap-materialize.service microvm@cp-1.service"

# Acceptance test: delete only the two bootstrap Secrets, run the reconciler,
# and prove both return. Values are never read or printed.
test-k3s-bootstrap-recovery:
    #!/usr/bin/env bash
    set -euo pipefail
    ssh -p 2222 erik@{{ip_kepler}} '
      set -euo pipefail
      ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null root@10.250.0.11 '\''
        set -euo pipefail
        k3s kubectl -n argocd delete secret homelab-gitops-repo
        k3s kubectl -n external-secrets delete secret vault-approle
        systemctl start k3s-bootstrap-secrets.service
        k3s kubectl -n argocd get secret homelab-gitops-repo -o name
        k3s kubectl -n external-secrets get secret vault-approle -o name
        k3s kubectl wait --for=condition=Ready clustersecretstore/vault-discovery --timeout=2m
      '\''
    '

# Rotate ESO's dedicated AppRole secret ID and capture both k3s bootstrap
# credentials directly into sops. Secret values never enter argv or stdout.
capture-k3s-bootstrap-secrets:
    #!/usr/bin/env bash
    set -euo pipefail
    token=$(sops --decrypt --extract '["vault_root_token"]' secrets/sops/secrets.yaml)
    secret_id=$(
      printf '%s\n' "$token" | ssh -p 2222 erik@{{ip_discovery}} '
        set -euo pipefail
        IFS= read -r token
        cfg=$(mktemp)
        trap "rm -f $cfg" EXIT
        printf "X-Vault-Token: %s\n" "$token" > "$cfg"
        unset token
        chmod 600 "$cfg"
        curl --header @"$cfg" --silent --show-error --fail --request POST \
          "http://127.0.0.1:8200/v1/auth/approle/role/eso/secret-id" \
          | jq -er .data.secret_id
      '
    )
    unset token
    printf '%s' "$secret_id" | jq -Rs . \
      | sops set --value-stdin secrets/sops/secrets.yaml '["k3s_bootstrap"]["vault_approle_secret_id"]'
    unset secret_id
    kubectl --context homelab -n argocd get secret homelab-gitops-repo \
      -o jsonpath='{.data.sshPrivateKey}' \
      | base64 --decode \
      | jq -Rs . \
      | sops set --value-stdin secrets/sops/secrets.yaml '["k3s_bootstrap"]["argocd_repo_ssh_key"]'
    echo ":: k3s bootstrap credentials encrypted in sops"

# Mint lane-scoped ESO AppRole credentials after homelab-iac has applied the
# policies/roles. Values travel only through stdin and encrypted Sops writes.
capture-k3s-vault-lane-secrets:
    #!/usr/bin/env bash
    set -euo pipefail
    token=$(sops --decrypt --extract '["vault_root_token"]' secrets/sops/secrets.yaml)
    for lane in platform homelab home-services; do
      credentials=$(
        printf '%s\n%s\n' "$token" "$lane" | ssh -p 2222 erik@{{ip_discovery}} '
          set -euo pipefail
          IFS= read -r token
          IFS= read -r lane
          case "$lane" in platform|homelab|home-services) ;; *) exit 2 ;; esac
          cfg=$(mktemp)
          trap "rm -f $cfg" EXIT
          printf "X-Vault-Token: %s\n" "$token" > "$cfg"
          unset token
          chmod 600 "$cfg"
          role_id=$(curl --header @"$cfg" --silent --show-error --fail \
            "http://127.0.0.1:8200/v1/auth/approle/role/eso-$lane/role-id" | jq -er .data.role_id)
          secret_id=$(curl --header @"$cfg" --silent --show-error --fail --request POST \
            "http://127.0.0.1:8200/v1/auth/approle/role/eso-$lane/secret-id" | jq -er .data.secret_id)
          jq -cn --arg role_id "$role_id" --arg secret_id "$secret_id" "\$ARGS.named"
        '
      )
      lane_key=${lane//-/_}
      role_path='["k3s_bootstrap"]["vault_approle_'"$lane_key"'_role_id"]'
      secret_path='["k3s_bootstrap"]["vault_approle_'"$lane_key"'_secret_id"]'
      jq -er .role_id <<<"$credentials" | jq -Rs . \
        | sops set --value-stdin secrets/sops/secrets.yaml "$role_path"
      jq -er .secret_id <<<"$credentials" | jq -Rs . \
        | sops set --value-stdin secrets/sops/secrets.yaml "$secret_path"
      unset credentials
    done
    unset token
    echo ":: lane AppRole credentials encrypted in sops"
