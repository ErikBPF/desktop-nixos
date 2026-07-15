#!/usr/bin/env bash
# Manifest-bound Discovery AdGuard outage drill. Rootless except local netns sudo -n.
set -euo pipefail
[ "$#" -ge 7 ] || { echo "usage: $0 plan|execute OBSERVATION KNOWN_HOSTS RDISC6 CLIENT OBSERVER CALLBACK [RUN_DIR AUTHORIZATION_SHA256]" >&2;exit 2; }
mode=$1;observation=$2;known_hosts=$3;rdisc6=$4;client=$5;observer=$6;callback=$7;run_dir=${8:-};authorization=${9:-}
[ -f "$observation" ] && [ -f "$known_hosts" ] && [ ! -L "$known_hosts" ] && [ "$(stat -c %u "$known_hosts")" = "$(id -u)" ] && [ "$(stat -c %a "$known_hosts")" = 400 ] || exit 2
[ -x "$rdisc6" ] && [ -x "$client" ] && [ -x "$observer" ] && [ -x "$callback" ] || exit 2
sha(){ sha256sum "$1"|cut -d' ' -f1; }
canonical=$(jq -cS . "$observation")
jq -e '.version==3 and .client.persistent_macvlan==true and .client.overlays==[] and (.ipv6.router|test("^fe80:")) and (.ipv6.prefix|test("/64$")) and (.ipv6.rdnss|test(":")) and .ipv6.router_lifetime=="positive" and .ipv6.rdnss_lifetime=="positive" and .resolvers.nameservers==[.ipv6.rdnss,"192.168.10.210","192.168.10.230"] and .resolvers.options==["timeout:2","attempts:1"] and .probe_contract=={filter_template:"{nonce}.doubleclick.net A",fleet_templates:["{nonce}.homelab.pastelariadev.com A","{nonce}.homelab.pastelariadev.com AAAA"],negative_template:"{nonce}.invalid A",public_templates:["{nonce}.1-1-1-1.sslip.io A","{nonce}.2606-4700-4700--1111.sslip.io AAAA"],resolvers:["gateway","adguard","kepler","system"],transports:["udp","tcp"]} and all(.probe_evidence[];test("^[0-9a-f]{64}$")) and (.probe_evidence|keys)==["classifications_sha256","nonce_sha256","qnames_sha256","results_sha256"] and (.failover_bound_ms>0 and .failover_bound_ms<=10000) and (.containers|length==5) and ([.containers[].name]|sort)==["adguard","adguard-exporter","k8s-apiserver","swag","swag-init"]' >/dev/null <<<"$canonical" || { echo "p3-outage-drill: BLOCKED: observation contract differs" >&2;exit 1; }
inventory_sha=$(printf %s "$canonical"|sha256sum|cut -d' ' -f1)
network_contract_sha=$(jq -cS '{ipv6,probe_contract,resolvers}' <<<"$canonical"|sha256sum|cut -d' ' -f1)
plan=$(jq -cnS --arg inventory "$inventory_sha" --arg network_contract "$network_contract_sha" --argjson probe_evidence "$(jq -cS .probe_evidence <<<"$canonical")" --arg known_hosts "$(sha "$known_hosts")" --arg client "$(sha "$client")" --arg observer "$(sha "$observer")" --arg drill "$(sha "$0")" --arg callback "$(sha "$callback")" --arg rdisc6 "$(sha "$rdisc6")" '{actions:["verify-bindings","fresh-observe","stop-adguard-exporter","stop-adguard","prove-failover","restore-adguard","restore-adguard-exporter","verify-invariants"],bindings:{callback_sha256:$callback,client_sha256:$client,drill_sha256:$drill,known_hosts_sha256:$known_hosts,observer_sha256:$observer,rdisc6_sha256:$rdisc6},evidence_phases:["outage","postrestore"],inventory_sha256:$inventory,mode:"approved-outage-drill",network_contract_sha256:$network_contract,probe_evidence:$probe_evidence,resources:["adguard-exporter","adguard"],version:3}')
hash=$(printf %s "$plan"|sha256sum|cut -d' ' -f1)
if [ "$mode" = plan ];then jq -cnS --argjson manifest "$plan" --arg manifest_sha256 "$hash" '{manifest:$manifest,manifest_sha256:$manifest_sha256}';exit 0;fi
[ "$mode" = execute ] && [ "$#" -eq 9 ] || { echo "p3-outage-drill: BLOCKED: authorization differs" >&2;exit 1; }
[ ! -e "$run_dir" ];mkdir -m 0700 "$run_dir"
journal=$run_dir/journal.jsonl;: >"$journal";chmod 0600 "$journal"
record(){ jq -cnS --arg event "$1" --arg status "$2" --arg manifest_sha256 "$hash" '{event:$event,manifest_sha256:$manifest_sha256,status:$status,version:1}' >>"$journal"; }
finish_artifact(){ local name=$1 status=$2 tmp postrestore_results_sha=;if [[ ${outage_start:-} =~ ^[0-9]+$ ]];then postrestore_results_sha=$(printf %b "${postrestore_evidence:-}"|sha256sum|cut -d' ' -f1);fi;tmp=$(mktemp "$run_dir/.artifact.XXXXXX");jq -cnS --arg manifest_sha256 "$hash" --arg status "$status" --arg outage_results_sha256 "${frozen_outage_results_sha256:-}" --arg postrestore_results_sha256 "$postrestore_results_sha" --argjson elapsed_ms "${elapsed:-null}" --argjson bound_ms "${bound:-null}" --argjson original_failure_rc "${original_failure_rc:-null}" --argjson recovery_failed "${recovery_failed:-false}" '{actual_elapsed_ms:$elapsed_ms,failover_bound_ms:$bound_ms,manifest_sha256:$manifest_sha256,original_failure_rc:$original_failure_rc,outage_results_sha256:(if $outage_results_sha256=="" then null else $outage_results_sha256 end),postrestore_results_sha256:(if $postrestore_results_sha256=="" then null else $postrestore_results_sha256 end),recovery_failed:$recovery_failed,status:$status,version:3}' >"$tmp";chmod 0600 "$tmp";mv -n "$tmp" "$run_dir/$name" || { rm -f "$tmp";return 1; }; }
[ "$authorization" = "$hash" ] || { finish_artifact failure.json authorization-drift;echo "p3-outage-drill: BLOCKED: authorization differs" >&2;exit 1; }
for binding in "$known_hosts" "$client" "$observer" "$0" "$callback" "$rdisc6";do [ -r "$binding" ] || exit 1;done
[ "$(sha "$known_hosts")" = "$(jq -r .bindings.known_hosts_sha256 <<<"$plan")" ] && [ "$(sha "$client")" = "$(jq -r .bindings.client_sha256 <<<"$plan")" ] && [ "$(sha "$observer")" = "$(jq -r .bindings.observer_sha256 <<<"$plan")" ] && [ "$(sha "$0")" = "$(jq -r .bindings.drill_sha256 <<<"$plan")" ] && [ "$(sha "$callback")" = "$(jq -r .bindings.callback_sha256 <<<"$plan")" ] && [ "$(sha "$rdisc6")" = "$(jq -r .bindings.rdisc6_sha256 <<<"$plan")" ] || { finish_artifact failure.json binding-drift;exit 1; }
remote_ip=$(jq -r .remote.ip <<<"$canonical");namespace=$(jq -r .client.namespace <<<"$canonical");client_interface=$(jq -r .client.interface <<<"$canonical");bound=$(jq -r .failover_bound_ms <<<"$canonical");rdnss=$(jq -r .ipv6.rdnss <<<"$canonical")
fresh=$("$observer" "$namespace" "$client_interface" "$remote_ip" "$bound" "$known_hosts" "$rdisc6" "$client" "$callback")
[ "$(jq -cS 'del(.probe_evidence)' <<<"$fresh")" = "$(jq -cS 'del(.probe_evidence)' <<<"$canonical")" ] && [ "$(jq -r .probe_evidence.nonce_sha256 <<<"$fresh")" != "$(jq -r .probe_evidence.nonce_sha256 <<<"$canonical")" ] && [ "$(jq -r .probe_evidence.qnames_sha256 <<<"$fresh")" != "$(jq -r .probe_evidence.qnames_sha256 <<<"$canonical")" ] && [ "$(jq -r .probe_evidence.results_sha256 <<<"$fresh")" != "$(jq -r .probe_evidence.results_sha256 <<<"$canonical")" ] && [ "$(jq -r .probe_evidence.classifications_sha256 <<<"$fresh")" = "$(jq -r .probe_evidence.classifications_sha256 <<<"$canonical")" ] || { finish_artifact failure.json inventory-drift;exit 1; }
ssh_opts=(-p 2222 -o BatchMode=yes -o ConnectTimeout=8 -o ConnectionAttempts=1 -o StrictHostKeyChecking=yes -o UserKnownHostsFile="$known_hosts" -o GlobalKnownHostsFile=/dev/null);remote=(timeout 12 ssh "${ssh_opts[@]}" "erik@$remote_ip")
adguard_id=$(jq -r '.containers[]|select(.name=="adguard")|.id' <<<"$canonical");exporter_id=$(jq -r '.containers[]|select(.name=="adguard-exporter")|.id' <<<"$canonical")
mutated=false;emit=false;tmp=$(mktemp);outage_evidence=;postrestore_evidence=;evidence_phase=outage;enforce_deadline=false;cleanup(){ rm -f "$tmp"; };trap cleanup EXIT INT TERM
deadline_check(){ if ! $enforce_deadline;then return 0;fi;[ "$(date +%s%3N)" -le "${outage_deadline:-0}" ]; }
check_dns_matrix() {
  local resolver=$1 transport=$2 name type _expected_status contract out answers nonce rc dns_status count_class classification qname_sha evidence_line;nonce=$(od -An -N16 -tx1 /dev/urandom|tr -d ' \n')
  local -a args=();[ "$resolver" != system ]&&args+=(@"$resolver");[ "$transport" = tcp ]&&args+=(+tcp)
  while read -r name type _expected_status contract;do
    deadline_check;name=${name//\{nonce\}/$nonce};if out=$(sudo -n ip netns exec "$namespace" dig "${args[@]}" +time=2 +tries=1 "$name" "$type");then rc=0;else rc=$?;fi
    [ "$rc" -eq 0 ];dns_status=$(sed -n 's/.*status: \([^,]*\).*/\1/p' <<<"$out"|head -1);answers=$(sed -n 's/.*ANSWER: \([0-9]*\).*/\1/p' <<<"$out"|head -1);[[ $answers =~ ^[0-9]+$ ]];if [ "$answers" -eq 0 ];then count_class=zero;else count_class=positive;fi
    case $contract in
      fleet-a) [ "$dns_status" = NOERROR ]&&[ "$count_class" = positive ]&&grep -q '192\.168\.10\.210' <<<"$out";classification="fleet-a";;
      fleet-aaaa) [ "$dns_status" = NOERROR ]&&[ "$count_class" = zero ];classification="nodata";;
      external) [ "$dns_status" = NOERROR ]&&[ "$count_class" = positive ];classification="external-positive";;
      nxdomain) [ "$dns_status" = NXDOMAIN ]&&[ "$count_class" = zero ];classification="nxdomain";;
      # Filtering accepts status: NXDOMAIN with zero answers or NOERROR with 0.0.0.0.
      filtered) if [ "$dns_status" = NXDOMAIN ]&&[ "$count_class" = zero ];then classification="filtered-nxdomain";elif [ "$dns_status" = NOERROR ]&&grep -q '0\.0\.0\.0' <<<"$out";then classification="filtered-null";else return 1;fi;;
    esac
    qname_sha=$(printf %s "$name"|sha256sum|cut -d' ' -f1);evidence_line="$resolver:$transport:$type:$contract:observed_rc=$rc:observed_status=$dns_status:answer_count_class=$count_class:answer_classification=$classification:qname_sha256=$qname_sha\n";if [ "$evidence_phase" = outage ];then outage_evidence+="$evidence_line";else postrestore_evidence+="$evidence_line";fi;deadline_check
  done <<'EOF'
{nonce}.homelab.pastelariadev.com A NOERROR fleet-a
{nonce}.homelab.pastelariadev.com AAAA NOERROR fleet-aaaa
{nonce}.1-1-1-1.sslip.io A NOERROR external
{nonce}.2606-4700-4700--1111.sslip.io AAAA NOERROR external
{nonce}.invalid A NXDOMAIN nxdomain
{nonce}.doubleclick.net A ANY filtered
EOF
}
postrestore_identity() {
  local post nonmutable_before nonmutable_after mutable_before mutable_after
  post=$("$observer" "$namespace" "$client_interface" "$remote_ip" "$bound" "$known_hosts" "$rdisc6" "$client" "$callback") || return 1
  postrestore_evidence+="observer_results_sha256=$(jq -r .probe_evidence.results_sha256 <<<"$post")\n"
  [ "$(jq -cS 'del(.containers,.probe_evidence)' <<<"$post")" = "$(jq -cS 'del(.containers,.probe_evidence)' <<<"$canonical")" ] || return 1
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
restored_operational_checks() {
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
freeze_outage_evidence() {
  if [ -z "${frozen_outage_results_sha256:-}" ];then frozen_outage_results_sha256=$(printf %b "$outage_evidence"|sha256sum|cut -d' ' -f1);fi
  evidence_phase=postrestore
}
recover() {
  local original=$? ok=false state attempt postrestore_rc=0
  original_failure_rc=$original;recovery_failed=false
  if [[ ${outage_start:-} =~ ^[0-9]+$ ]];then elapsed=$(($(date +%s%3N)-outage_start));fi
  freeze_outage_evidence
  trap - EXIT INT TERM;enforce_deadline=false
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
    if ! $ok;then recovery_failed=true;original=1;fi
    if $ok;then
      record postrestore-checks started
      postrestore_operational || postrestore_rc=$?
      if [ "$postrestore_rc" -eq 0 ];then record postrestore-checks passed;else record postrestore-checks failed;recovery_failed=true;original=1;fi
    fi
  fi
  if [ "$original" -eq 0 ] && $emit;then finish_artifact result.json passed;else finish_artifact failure.json failed || true;fi
  cleanup;exit "$original"
}
postrestore_operational(){ restored_operational_checks; }
trap recover EXIT INT TERM
record stop-exporter started;mutated=true
"${remote[@]}" "docker stop $exporter_id" >/dev/null
record stop-exporter passed;record stop-adguard started
"${remote[@]}" "docker stop $adguard_id" >/dev/null
outage_start=$(date +%s%3N);outage_deadline=$((outage_start+bound));enforce_deadline=true
record stop-adguard passed;record stopped-gate started
[ "$("${remote[@]}" "docker inspect -f '{{.State.Status}}' $exporter_id $adguard_id"|tr '\n' ' ')" = "exited exited " ]
record stopped-gate passed;record failover-probe started
for transport in udp tcp;do check_dns_matrix system "$transport";done
record failover-probe passed;record secondary-matrix started
for transport in udp tcp;do check_dns_matrix "$rdnss" "$transport";check_dns_matrix 192.168.10.230 "$transport";done
deadline_check;elapsed=$(($(date +%s%3N)-outage_start))
record secondary-matrix passed;emit=true;record outage-proof passed;trap - EXIT INT TERM;recover
