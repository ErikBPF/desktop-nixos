#!/usr/bin/env bash
# Manifest-bound Discovery AdGuard outage drill. Rootless except local netns sudo -n.
set -euo pipefail
[ "$#" -ge 7 ] || { echo "usage: $0 plan|execute OBSERVATION KNOWN_HOSTS RDISC6 CLIENT OBSERVER CALLBACK [RUN_DIR AUTHORIZATION_SHA256]" >&2;exit 2; }
mode=$1;observation=$2;known_hosts=$3;rdisc6=$4;client=$5;observer=$6;callback=$7;run_dir=${8:-};authorization=${9:-}
[ -f "$observation" ] && [ -f "$known_hosts" ] && [ ! -L "$known_hosts" ] && [ "$(stat -c %u "$known_hosts")" = "$(id -u)" ] && [ "$(stat -c %a "$known_hosts")" = 400 ] || exit 2
[ -x "$rdisc6" ] && [ -x "$client" ] && [ -x "$observer" ] && [ -x "$callback" ] || exit 2
sha(){ sha256sum "$1"|cut -d' ' -f1; }
canonical=$(jq -cS . "$observation")
jq -e '.version==3 and .client.persistent_macvlan==true and .client.overlays==[] and .dhcp_dns==["192.168.10.210","192.168.10.230"] and .ipv6=={default_routes:[],ra_probe:"bounded-no-ra",rdnss:[]} and (.failover_bound_ms>0 and .failover_bound_ms<=10000) and (.containers|length==5) and ([.containers[].name]|sort)==["adguard","adguard-exporter","k8s-apiserver","swag","swag-init"]' >/dev/null <<<"$canonical" || { echo "p3-outage-drill: BLOCKED: observation contract differs" >&2;exit 1; }
inventory_sha=$(printf %s "$canonical"|sha256sum|cut -d' ' -f1)
plan=$(jq -cnS --arg inventory "$inventory_sha" --arg known_hosts "$(sha "$known_hosts")" --arg client "$(sha "$client")" --arg observer "$(sha "$observer")" --arg drill "$(sha "$0")" --arg callback "$(sha "$callback")" --arg rdisc6 "$(sha "$rdisc6")" '{actions:["verify-bindings","fresh-observe","stop-adguard-exporter","stop-adguard","prove-failover","restore-adguard","restore-adguard-exporter","verify-invariants"],bindings:{callback_sha256:$callback,client_sha256:$client,drill_sha256:$drill,known_hosts_sha256:$known_hosts,observer_sha256:$observer,rdisc6_sha256:$rdisc6},inventory_sha256:$inventory,mode:"approved-outage-drill",resources:["adguard-exporter","adguard"],version:2}')
hash=$(printf %s "$plan"|sha256sum|cut -d' ' -f1)
if [ "$mode" = plan ];then jq -cnS --argjson manifest "$plan" --arg manifest_sha256 "$hash" '{manifest:$manifest,manifest_sha256:$manifest_sha256}';exit 0;fi
[ "$mode" = execute ] && [ "$#" -eq 9 ] || { echo "p3-outage-drill: BLOCKED: authorization differs" >&2;exit 1; }
[ ! -e "$run_dir" ];mkdir -m 0700 "$run_dir"
journal=$run_dir/journal.jsonl;: >"$journal";chmod 0600 "$journal"
record(){ jq -cnS --arg event "$1" --arg status "$2" --arg manifest_sha256 "$hash" '{event:$event,manifest_sha256:$manifest_sha256,status:$status,version:1}' >>"$journal"; }
finish_artifact(){ local name=$1 status=$2 tmp;tmp=$(mktemp "$run_dir/.artifact.XXXXXX");jq -cnS --arg manifest_sha256 "$hash" --arg status "$status" --argjson elapsed_ms "${elapsed:-null}" --argjson bound_ms "${bound:-null}" '{actual_elapsed_ms:$elapsed_ms,failover_bound_ms:$bound_ms,manifest_sha256:$manifest_sha256,status:$status,version:2}' >"$tmp";chmod 0600 "$tmp";mv -n "$tmp" "$run_dir/$name" || { rm -f "$tmp";return 1; }; }
[ "$authorization" = "$hash" ] || { finish_artifact failure.json authorization-drift;echo "p3-outage-drill: BLOCKED: authorization differs" >&2;exit 1; }
for binding in "$known_hosts" "$client" "$observer" "$0" "$callback" "$rdisc6";do [ -r "$binding" ] || exit 1;done
[ "$(sha "$known_hosts")" = "$(jq -r .bindings.known_hosts_sha256 <<<"$plan")" ] && [ "$(sha "$client")" = "$(jq -r .bindings.client_sha256 <<<"$plan")" ] && [ "$(sha "$observer")" = "$(jq -r .bindings.observer_sha256 <<<"$plan")" ] && [ "$(sha "$0")" = "$(jq -r .bindings.drill_sha256 <<<"$plan")" ] && [ "$(sha "$callback")" = "$(jq -r .bindings.callback_sha256 <<<"$plan")" ] && [ "$(sha "$rdisc6")" = "$(jq -r .bindings.rdisc6_sha256 <<<"$plan")" ] || { finish_artifact failure.json binding-drift;exit 1; }
remote_ip=$(jq -r .remote.ip <<<"$canonical");namespace=$(jq -r .client.namespace <<<"$canonical");client_interface=$(jq -r .client.interface <<<"$canonical");bound=$(jq -r .failover_bound_ms <<<"$canonical")
fresh=$("$observer" "$namespace" "$client_interface" "$remote_ip" "$bound" "$known_hosts" "$rdisc6" "$client" "$callback")
[ "$(jq -cS . <<<"$fresh")" = "$canonical" ] || { finish_artifact failure.json inventory-drift;exit 1; }
ssh_opts=(-p 2222 -o BatchMode=yes -o ConnectTimeout=8 -o ConnectionAttempts=1 -o StrictHostKeyChecking=yes -o UserKnownHostsFile="$known_hosts");remote=(timeout 12 ssh "${ssh_opts[@]}" "erik@$remote_ip")
adguard_id=$(jq -r '.containers[]|select(.name=="adguard")|.id' <<<"$canonical");exporter_id=$(jq -r '.containers[]|select(.name=="adguard-exporter")|.id' <<<"$canonical")
mutated=false;emit=false;tmp=$(mktemp);cleanup(){ rm -f "$tmp"; };trap cleanup EXIT INT TERM
check_dns_matrix() {
  local resolver=$1 transport=$2 name type status contract out answers
  local -a transport_arg=();[ "$transport" = tcp ] && transport_arg=(+tcp)
  while read -r name type status contract;do
    out=$(sudo -n ip netns exec "$namespace" dig "${transport_arg[@]}" +time=2 +tries=1 @"$resolver" "$name" "$type")
    grep -q "status: $status" <<<"$out" || return 1
    answers=$(sed -n 's/.*ANSWER: \([0-9]*\).*/\1/p' <<<"$out"|head -1)
    case $contract in
      fleet-a) [ "${answers:-0}" -ge 1 ] && grep -q '192\.168\.10\.210' <<<"$out";;
      fleet-aaaa|nxdomain) [ "${answers:-0}" -eq 0 ];;
      external) [ "${answers:-0}" -ge 1 ];;
    esac || return 1
  done <<'EOF'
wildcard-test.homelab.pastelariadev.com A NOERROR fleet-a
wildcard-test.homelab.pastelariadev.com AAAA NOERROR fleet-aaaa
example.com A NOERROR external
example.com AAAA NOERROR external
p3-nonexistent.invalid A NXDOMAIN nxdomain
EOF
}
postrestore_identity() {
  local post nonmutable_before nonmutable_after mutable_before mutable_after
  post=$("$observer" "$namespace" "$client_interface" "$remote_ip" "$bound" "$known_hosts" "$rdisc6" "$client" "$callback") || return 1
  nonmutable_before=$(jq -cS '[.containers[]|select(.name!="adguard" and .name!="adguard-exporter")]' <<<"$canonical")
  nonmutable_after=$(jq -cS '[.containers[]|select(.name!="adguard" and .name!="adguard-exporter")]' <<<"$post")
  [ "$nonmutable_after" = "$nonmutable_before" ] || return 1
  mutable_before=$(jq -cS '[.containers[]|select(.name=="adguard" or .name=="adguard-exporter")|del(.state,.health,.restart_count)]' <<<"$canonical")
  mutable_after=$(jq -cS '[.containers[]|select(.name=="adguard" or .name=="adguard-exporter")|del(.state,.health,.restart_count)]' <<<"$post")
  [ "$mutable_after" = "$mutable_before" ] || return 1
  jq -e --argjson before "$canonical" '
    all(.containers[]|select(.name=="adguard" or .name=="adguard-exporter");
      . as $after | ($before.containers[]|select(.name==$after.name)|.restart_count) as $old |
      .state=="running" and (if .name=="adguard" then .health=="healthy" else .health==null or .health=="healthy" end) and .restart_count >= $old and .restart_count <= ($old+3))
  ' >/dev/null <<<"$post"
}
postrestore_operational() {
  local resolver transport filtered metrics family
  for resolver in 192.168.10.210 192.168.10.230;do for transport in udp tcp;do check_dns_matrix "$resolver" "$transport" || return 1;done;done
  sudo -n ip netns exec "$namespace" getent ahostsv4 discovery.homelab.pastelariadev.com >/dev/null || return 1
  filtered=$(sudo -n ip netns exec "$namespace" dig +time=2 +tries=1 @192.168.10.210 doubleclick.net A) || return 1
  grep -Eq '0\.0\.0\.0|status: NXDOMAIN' <<<"$filtered" || return 1
  exporter_metrics_ready || return 1
  "${remote[@]}" "curl -kfsS --max-time 5 --resolve grafana.homelab.pastelariadev.com:443:127.0.0.1 -H 'Host: grafana.homelab.pastelariadev.com' https://grafana.homelab.pastelariadev.com/ >/dev/null" || return 1
  sudo -n ip netns exec "$namespace" dig +time=2 +tries=1 @192.168.10.210 k8s.pastelariadev.com A|grep -q 'status: NOERROR' || return 1
}
exporter_metrics_ready() {
  local metrics family attempt;local ready
  for attempt in 1 2 3 4 5;do
    metrics=$("${remote[@]}" "ip=\$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $exporter_id); curl -fsS --max-time 3 http://\$ip:9618/metrics" 2>/dev/null||true)
    ready=true;for family in adguard_queries adguard_queries_blocked adguard_avg_processing_time_seconds;do grep -Eq "^# TYPE $family " <<<"$metrics" || ready=false;done
    $ready && return 0;sleep 1
  done
  return 1
}
recover() {
  local original=$? ok=false state attempt
  trap - EXIT INT TERM
  if $mutated;then
    for attempt in 1 2 3;do
      record recovery-attempt "$attempt"
      "${remote[@]}" "docker start $adguard_id" >/dev/null 2>&1 || { record recovery-outcome start-adguard-failed;continue; }
      state="";for _ in {1..30};do state=$("${remote[@]}" "docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' $adguard_id" 2>/dev/null||true);[ "$state" = healthy ]&&break;sleep 1;done
      [ "$state" = healthy ] || { record recovery-outcome health-failed;continue; }
      "${remote[@]}" "docker start $exporter_id" >/dev/null 2>&1 || { record recovery-outcome start-exporter-failed;continue; }
      exporter_metrics_ready || { record recovery-outcome exporter-readiness-failed;continue; }
      postrestore_identity || { record recovery-outcome identity-failed;continue; }
      record recovery-outcome restored;ok=true;break
    done
    $ok || original=1
    if $ok && [ "$original" -eq 0 ];then
      record postrestore-checks started
      postrestore_operational || original=1
      if [ "$original" -eq 0 ];then record postrestore-checks passed;else record postrestore-checks failed;fi
    fi
  fi
  if [ "$original" -eq 0 ] && $emit;then finish_artifact result.json passed;else finish_artifact failure.json failed || true;fi
  cleanup;exit "$original"
}
trap recover EXIT INT TERM
record stop-exporter started;mutated=true
"${remote[@]}" "docker stop $exporter_id" >/dev/null
record stop-exporter passed;record stop-adguard started
"${remote[@]}" "docker stop $adguard_id" >/dev/null
record stop-adguard passed;record stopped-gate started
[ "$("${remote[@]}" "docker inspect -f '{{.State.Status}}' $exporter_id $adguard_id"|tr '\n' ' ')" = "exited exited " ]
record stopped-gate passed;record failover-probe started
start=$(date +%s%3N);timeout_s=$(awk "BEGIN{print $bound/1000}")
timeout "$timeout_s" sudo -n ip netns exec "$namespace" getent ahostsv4 discovery.homelab.pastelariadev.com >/dev/null
elapsed=$(($(date +%s%3N)-start));[ "$elapsed" -le "$bound" ]
record failover-probe passed;record secondary-matrix started
for transport in udp tcp;do check_dns_matrix 192.168.10.230 "$transport";done
record secondary-matrix passed;emit=true;record outage-proof passed;trap - EXIT INT TERM;recover
