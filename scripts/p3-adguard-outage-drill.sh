#!/usr/bin/env bash
# Manifest-bound Discovery AdGuard outage drill. Rootless except local netns sudo -n.
set -euo pipefail
[ "$#" -ge 8 ] || { echo "usage: $0 plan|execute OBSERVATION KNOWN_HOSTS RDISC6 CLIENT OBSERVER CALLBACK HELPER_SOURCE [RUN_DIR AUTHORIZATION_SHA256]" >&2;exit 2; }
mode=$1;observation=$2;known_hosts=$3;rdisc6=$4;client=$5;observer=$6;callback=$7;helper_source=$8;run_dir=${9:-};authorization=${10:-}
[ -f "$observation" ] && [ -f "$known_hosts" ] && [ ! -L "$known_hosts" ] && [ "$(stat -c %u "$known_hosts")" = "$(id -u)" ] && [ "$(stat -c %a "$known_hosts")" = 400 ] || exit 2
[ -x "$rdisc6" ] && [ -x "$client" ] && [ -x "$observer" ] && [ -x "$callback" ] && [ -r "$helper_source" ] || exit 2
sha(){ sha256sum "$1"|cut -d' ' -f1; }
canonical=$(jq -cS . "$observation")
jq -e '.version==3 and .client.persistent_macvlan==true and .client.overlays==[] and (.ipv6.router|test("^fe80:")) and (.ipv6.prefix|test("/64$")) and (.ipv6.rdnss|test(":")) and .ipv6.router_lifetime=="positive" and .ipv6.rdnss_lifetime=="positive" and .resolvers.nameservers==[.ipv6.rdnss,"192.168.10.210","192.168.10.230"] and .resolvers.options==["timeout:2","attempts:1"] and .probe_contract=={filter_template:"{nonce}.doubleclick.net A",fleet_templates:["{nonce}.homelab.pastelariadev.com A","{nonce}.homelab.pastelariadev.com AAAA"],negative_template:"{nonce}.invalid A",public_templates:["{nonce}.1-1-1-1.sslip.io A","{nonce}.2606-4700-4700--1111.sslip.io AAAA"],resolvers:["gateway","adguard","kepler","system"],transports:["udp","tcp"]} and all(.probe_evidence[];test("^[0-9a-f]{64}$")) and (.probe_evidence|keys)==["classifications_sha256","nonce_sha256","qnames_sha256","results_sha256"] and (.failover_bound_ms>0 and .failover_bound_ms<=10000) and (.containers|length==5) and ([.containers[].name]|sort)==["adguard","adguard-exporter","k8s-apiserver","swag","swag-init"]' >/dev/null <<<"$canonical" || { echo "p3-outage-drill: BLOCKED: observation contract differs" >&2;exit 1; }
inventory_sha=$(printf %s "$canonical"|sha256sum|cut -d' ' -f1)
network_contract_sha=$(jq -cS '{ipv6,probe_contract,resolvers}' <<<"$canonical"|sha256sum|cut -d' ' -f1)
plan=$(jq -cnS --arg inventory "$inventory_sha" --arg network_contract "$network_contract_sha" --argjson probe_evidence "$(jq -cS .probe_evidence <<<"$canonical")" --arg known_hosts "$(sha "$known_hosts")" --arg client "$(sha "$client")" --arg observer "$(sha "$observer")" --arg drill "$(sha "$0")" --arg callback "$(sha "$callback")" --arg rdisc6 "$(sha "$rdisc6")" --arg helper "$(sha "$helper_source")" '{actions:["verify-bindings","fresh-observe","verify-helper-implementation","stop-adguard-exporter","stop-adguard","prove-required-core","diagnose-gateway-rdnss","restore-adguard","restore-adguard-exporter","verify-postrestore-gateway-adguard-kepler","verify-invariants"],bindings:{callback_sha256:$callback,client_sha256:$client,drill_sha256:$drill,helper_sha256:$helper,known_hosts_sha256:$known_hosts,observer_sha256:$observer,rdisc6_sha256:$rdisc6},diagnostic_workers:[{ordinal:1,resolver:"gateway-rdnss",transport:"udp"},{ordinal:2,resolver:"gateway-rdnss",transport:"tcp"}],evidence_phases:["outage-core","outage-diagnostic","postrestore"],inventory_sha256:$inventory,mode:"approved-outage-drill",network_contract_sha256:$network_contract,probe_contracts:[{contract:"fleet-a",name_template:"{nonce}.homelab.pastelariadev.com",type:"A"},{contract:"fleet-aaaa",name_template:"{nonce}.homelab.pastelariadev.com",type:"AAAA"},{contract:"external",name_template:"{nonce}.1-1-1-1.sslip.io",type:"A"},{contract:"external",name_template:"{nonce}.2606-4700-4700--1111.sslip.io",type:"AAAA"},{contract:"nxdomain",name_template:"{nonce}.invalid",type:"A"},{contract:"filtered",name_template:"{nonce}.doubleclick.net",type:"A"}],probe_evidence:$probe_evidence,required_workers:[{ordinal:1,resolver:"system",transport:"udp"},{ordinal:2,resolver:"system",transport:"tcp"},{ordinal:3,resolver:"kepler",transport:"udp"},{ordinal:4,resolver:"kepler",transport:"tcp"}],resources:["adguard-exporter","adguard"],shared_nonce:{generated_after:"stopped-gate",hash:"sha256",scope:"all-outage-workers"},version:4}')
hash=$(printf %s "$plan"|sha256sum|cut -d' ' -f1)
if [ "$mode" = plan ];then jq -cnS --argjson manifest "$plan" --arg manifest_sha256 "$hash" '{manifest:$manifest,manifest_sha256:$manifest_sha256}';exit 0;fi
[ "$mode" = execute ] && [ "$#" -eq 10 ] || { echo "p3-outage-drill: BLOCKED: authorization differs" >&2;exit 1; }
[ ! -e "$run_dir" ];mkdir -m 0700 "$run_dir"
journal=$run_dir/journal.jsonl;: >"$journal";chmod 0600 "$journal"
record(){ jq -cnS --arg event "$1" --arg status "$2" --arg manifest_sha256 "$hash" '{event:$event,manifest_sha256:$manifest_sha256,status:$status,version:1}' >>"$journal"; }
finish_artifact(){ local name=$1 status=$2 tmp postrestore_results_sha=;postrestore_evidence_rows=$(printf %b "${postrestore_evidence:-}"|sed '/^$/d'|wc -l);if [ "$postrestore_evidence_rows" -gt 0 ];then postrestore_results_sha=$(printf %b "$postrestore_evidence"|sha256sum|cut -d' ' -f1);fi;tmp=$(mktemp "$run_dir/.artifact.XXXXXX");jq -cnS --arg manifest_sha256 "$hash" --arg status "$status" --arg outage_results_sha256 "${frozen_outage_results_sha256:-}" --arg partial_outage_results_sha256 "${partial_outage_results_sha256:-}" --arg diagnostic_results_sha256 "${frozen_diagnostic_results_sha256:-}" --arg partial_diagnostic_results_sha256 "${partial_diagnostic_results_sha256:-}" --arg core_status "${core_evidence_status:-not-started}" --arg diagnostic_status "${diagnostic_evidence_status:-not-started}" --arg postrestore_status "${postrestore_status:-not-started}" --arg shared_nonce_sha256 "${outage_nonce_sha256:-}" --arg postrestore_results_sha256 "$postrestore_results_sha" --argjson core_rows "${core_evidence_rows:-0}" --argjson diagnostic_rows "${diagnostic_evidence_rows:-0}" --argjson postrestore_rows "${postrestore_evidence_rows:-0}" --argjson elapsed_ms "${elapsed:-null}" --argjson bound_ms "${bound:-null}" --argjson original_failure_rc "${original_failure_rc:-null}" --argjson recovery_failed "${recovery_failed:-false}" '{actual_elapsed_ms:$elapsed_ms,core_evidence:{rows:$core_rows,status:$core_status},core_partial_results_sha256:(if $partial_outage_results_sha256=="" then null else $partial_outage_results_sha256 end),core_results_sha256:(if $outage_results_sha256=="" then null else $outage_results_sha256 end),core_row_count:$core_rows,diagnostic_evidence:{rows:$diagnostic_rows,status:$diagnostic_status},diagnostic_results_sha256:(if $diagnostic_results_sha256=="" then null else $diagnostic_results_sha256 end),diagnostic_row_count:$diagnostic_rows,diagnostic_status:$diagnostic_status,failover_bound_ms:$bound_ms,manifest_sha256:$manifest_sha256,original_failure_rc:$original_failure_rc,outage_results_sha256:(if $outage_results_sha256=="" then null else $outage_results_sha256 end),partial_diagnostic_results_sha256:(if $partial_diagnostic_results_sha256=="" then null else $partial_diagnostic_results_sha256 end),partial_outage_results_sha256:(if $partial_outage_results_sha256=="" then null else $partial_outage_results_sha256 end),postrestore_evidence:{rows:$postrestore_rows,status:$postrestore_status},postrestore_row_count:$postrestore_rows,postrestore_results_sha256:(if $postrestore_results_sha256=="" then null else $postrestore_results_sha256 end),postrestore_status:$postrestore_status,recovery_failed:$recovery_failed,shared_nonce_sha256:(if $shared_nonce_sha256=="" then null else $shared_nonce_sha256 end),status:$status,version:4}' >"$tmp";chmod 0600 "$tmp";mv -n "$tmp" "$run_dir/$name" || { rm -f "$tmp";return 1; }; }
[ "$authorization" = "$hash" ] || { finish_artifact failure.json authorization-drift;echo "p3-outage-drill: BLOCKED: authorization differs" >&2;exit 1; }
for binding in "$known_hosts" "$client" "$observer" "$0" "$callback" "$rdisc6" "$helper_source";do [ -r "$binding" ] || exit 1;done
[ "$(sha "$known_hosts")" = "$(jq -r .bindings.known_hosts_sha256 <<<"$plan")" ] && [ "$(sha "$client")" = "$(jq -r .bindings.client_sha256 <<<"$plan")" ] && [ "$(sha "$observer")" = "$(jq -r .bindings.observer_sha256 <<<"$plan")" ] && [ "$(sha "$0")" = "$(jq -r .bindings.drill_sha256 <<<"$plan")" ] && [ "$(sha "$callback")" = "$(jq -r .bindings.callback_sha256 <<<"$plan")" ] && [ "$(sha "$rdisc6")" = "$(jq -r .bindings.rdisc6_sha256 <<<"$plan")" ] && [ "$(sha "$helper_source")" = "$(jq -r .bindings.helper_sha256 <<<"$plan")" ] || { finish_artifact failure.json binding-drift;exit 1; }
remote_ip=$(jq -r .remote.ip <<<"$canonical");namespace=$(jq -r .client.namespace <<<"$canonical");client_interface=$(jq -r .client.interface <<<"$canonical");bound=$(jq -r .failover_bound_ms <<<"$canonical");rdnss=$(jq -r .ipv6.rdnss <<<"$canonical")
fresh=$("$observer" "$namespace" "$client_interface" "$remote_ip" "$bound" "$known_hosts" "$rdisc6" "$client" "$callback")
[ "$(jq -cS 'del(.probe_evidence)' <<<"$fresh")" = "$(jq -cS 'del(.probe_evidence)' <<<"$canonical")" ] && [ "$(jq -r .probe_evidence.nonce_sha256 <<<"$fresh")" != "$(jq -r .probe_evidence.nonce_sha256 <<<"$canonical")" ] && [ "$(jq -r .probe_evidence.qnames_sha256 <<<"$fresh")" != "$(jq -r .probe_evidence.qnames_sha256 <<<"$canonical")" ] && [ "$(jq -r .probe_evidence.results_sha256 <<<"$fresh")" != "$(jq -r .probe_evidence.results_sha256 <<<"$canonical")" ] && [ "$(jq -r .probe_evidence.classifications_sha256 <<<"$fresh")" = "$(jq -r .probe_evidence.classifications_sha256 <<<"$canonical")" ] || { finish_artifact failure.json inventory-drift;exit 1; }
ssh_opts=(-p 2222 -o BatchMode=yes -o ConnectTimeout=8 -o ConnectionAttempts=1 -o StrictHostKeyChecking=yes -o UserKnownHostsFile="$known_hosts" -o GlobalKnownHostsFile=/dev/null);ssh_command=(ssh "${ssh_opts[@]}" "erik@$remote_ip");remote=(timeout 12 "${ssh_command[@]}")
expected_helper_identity=$(jq -cnS --arg implementation_sha256 "$(sha "$helper_source")" '{implementation_sha256:$implementation_sha256,version:1}')
remote_helper_identity=$(timeout 12 "${ssh_command[@]}" "sudo -n discovery-stateful-adguard-inventory implementation-sha256") || { finish_artifact failure.json helper-identity-failed;exit 1; }
[ "$remote_helper_identity" = "$expected_helper_identity" ] || { finish_artifact failure.json helper-identity-drift;exit 1; }
adguard_id=$(jq -r '.containers[]|select(.name=="adguard")|.id' <<<"$canonical");exporter_id=$(jq -r '.containers[]|select(.name=="adguard-exporter")|.id' <<<"$canonical")
mutated=false;emit=false;outage_complete=false;tmp=$(mktemp);outage_evidence=;diagnostic_evidence=;postrestore_evidence=;postrestore_status=not-started;postrestore_evidence_rows=0;enforce_deadline=false;worker_pids=();worker_files=();diagnostic_pids=();diagnostic_files=();diagnostic_terminal_files=();cleanup(){ rm -f "$tmp"; };trap cleanup EXIT INT TERM
deadline_check(){ if ! $enforce_deadline;then return 0;fi;[ "$(date +%s%3N)" -le "${outage_deadline:-0}" ]; }
timeout_duration(){
  local milliseconds=$1;[[ $milliseconds =~ ^[1-9][0-9]*$ ]] || return 1
  printf '%d.%03ds' "$((milliseconds/1000))" "$((milliseconds%1000))"
}
deadline_duration(){ local deadline=$1 remaining;remaining=$((deadline-$(date +%s%3N)));[ "$remaining" -gt 0 ] || return 1;timeout_duration "$remaining"; }
deadline_sleep(){ local deadline=$1 requested=$2 remaining duration;[[ $requested =~ ^[1-9][0-9]*$ ]] || return 1;remaining=$((deadline-$(date +%s%3N)));[ "$remaining" -gt 0 ] || return 1;[ "$requested" -le "$remaining" ] || requested=$remaining;duration=$(timeout_duration "$requested");sleep "$duration"; }
recovery_run(){ local duration;duration=$(deadline_duration "$recovery_deadline") || return 1;timeout "$duration" "$@"; }
recovery_capture(){ local duration capture_file rc;duration=$(deadline_duration "$recovery_deadline") || return 1;capture_file=$(mktemp "$run_dir/.recovery-capture.XXXXXX");chmod 0600 "$capture_file";if timeout "$duration" "$@" >"$capture_file";then rc=0;else rc=$?;fi;REPLY=$(<"$capture_file");rm -f "$capture_file";return "$rc"; }
check_dns_matrix() {
  local ordinal=$1 resolver=$2 transport=$3 destination=$4 nonce=$5 name type _expected_status contract out answers rc dns_status count_class classification qname_sha evidence_line now remaining duration row=0 answer_rrs rr_count a_values a_count unique_a_values
  [[ $nonce =~ ^[0-9a-f]{32}$ ]] || return 1
  local -a args=();if [ "$resolver" != system ];then args+=(@"$resolver");fi;if [ "$transport" = tcp ];then args+=(+tcp);fi
  while read -r name type _expected_status contract;do
    deadline_check || return 1
    if $enforce_deadline;then now=$(date +%s%3N) || return 1;remaining=$((outage_deadline-now));[ "$remaining" -gt 0 ] || return 1;elif [[ ${recovery_deadline:-} =~ ^[0-9]+$ ]];then now=$(date +%s%3N) || return 1;remaining=$((recovery_deadline-now));[ "$remaining" -gt 0 ] || return 1;else remaining=2000;fi
    duration=$(timeout_duration "$remaining") || return 1;name=${name//\{nonce\}/$nonce}
    worker_query_tmp="${destination}.query";: >"$worker_query_tmp" || return 1;chmod 0600 "$worker_query_tmp" || return 1
    timeout "$duration" sudo -n ip netns exec "$namespace" dig "${args[@]}" +time=1 +tries=1 "$name" "$type" >"$worker_query_tmp" & active_timeout_pid=$!
    if wait "$active_timeout_pid";then rc=0;else rc=$?;fi;active_timeout_pid=;out=$(<"$worker_query_tmp") || return 1;rm -f "$worker_query_tmp" || return 1;worker_query_tmp=
    [ "$rc" -eq 0 ] || return 1
    dns_status=$(sed -n 's/.*status: \([^,]*\).*/\1/p' <<<"$out") || return 1
    [[ $dns_status != *$'\n'* && $dns_status =~ ^(NOERROR|NXDOMAIN)$ ]] || return 1
    answers=$(sed -n 's/.*ANSWER: \([^,;[:space:]]*\).*/\1/p' <<<"$out") || return 1
    [[ $answers != *$'\n'* && $answers =~ ^[0-9]+$ ]] || return 1
    if [ "$answers" -eq 0 ];then count_class=zero;else count_class=positive;fi
    case $contract in
      fleet-a) answer_rrs=$(awk '/^;; ANSWER SECTION:/{inside=1;next}/^;;/{if(inside)exit}inside&&NF{print}' <<<"$out") || return 1;rr_count=$(printf '%s\n' "$answer_rrs"|sed '/^$/d'|wc -l);a_values=$(awk '$4=="A"{print $5}' <<<"$answer_rrs") || return 1;a_count=$(printf '%s\n' "$a_values"|sed '/^$/d'|wc -l);unique_a_values=$(printf '%s\n' "$a_values"|sed '/^$/d'|LC_ALL=C sort -u);if [ "$dns_status" != NOERROR ]||[ "$count_class" != positive ]||[ "$rr_count" -ne "$answers" ]||[ "$a_count" -ne "$answers" ]||[ "$unique_a_values" != 192.168.10.210 ];then return 1;fi;classification="fleet-a";;
      fleet-aaaa) if [ "$dns_status" != NOERROR ]||[ "$count_class" != zero ];then return 1;fi;classification="nodata";;
      external) if [ "$dns_status" != NOERROR ]||[ "$count_class" != positive ];then return 1;fi;classification="external-positive";;
      nxdomain) if [ "$dns_status" != NXDOMAIN ]||[ "$count_class" != zero ];then return 1;fi;classification="nxdomain";;
      # Filtering accepts status: NXDOMAIN with zero answers or NOERROR with 0.0.0.0.
      filtered) if [ "$dns_status" = NXDOMAIN ]&&[ "$count_class" = zero ];then classification="filtered-nxdomain";elif [ "$dns_status" = NOERROR ]&&grep -q '0\.0\.0\.0' <<<"$out";then classification="filtered-null";else return 1;fi;;
      *) return 1;;
    esac
    qname_sha=$(printf %s "$name"|sha256sum|cut -d' ' -f1) || return 1
    evidence_line="$resolver:$transport:$type:$contract:observed_rc=$rc:observed_status=$dns_status:answer_count_class=$count_class:answer_classification=$classification:qname_sha256=$qname_sha"
    printf '%02d:%02d:%s\n' "$ordinal" "$((++row))" "$evidence_line" >>"$destination" || return 1
    deadline_check || return 1
  done <<'EOF'
{nonce}.homelab.pastelariadev.com A NOERROR fleet-a
{nonce}.homelab.pastelariadev.com AAAA NOERROR fleet-aaaa
{nonce}.1-1-1-1.sslip.io A NOERROR external
{nonce}.2606-4700-4700--1111.sslip.io AAAA NOERROR external
{nonce}.invalid A NXDOMAIN nxdomain
{nonce}.doubleclick.net A ANY filtered
EOF
}
worker_write_terminal(){ local row_count status tmp_terminal;[ -n "${worker_terminal_file:-}" ]||return 0;[ "${worker_terminal_written:-false}" = false ]||return 0;row_count=$(wc -l <"$worker_rows_file");case ${worker_rc_class:-failed}:$row_count in success:6) status=complete;;cancelled:*) status=cancelled;;*:0) status=failed;;*) status=partial;;esac;tmp_terminal=$(mktemp "$run_dir/.diagnostic-terminal.XXXXXX")||return 1;jq -cnS --argjson ordinal "$worker_terminal_ordinal" --arg resolver_label "$worker_terminal_resolver_label" --arg transport "$worker_terminal_transport" --arg rc_class "${worker_rc_class:-failed}" --arg status "$status" --argjson row_count "$row_count" '{ordinal:$ordinal,rc_class:$rc_class,resolver_label:$resolver_label,row_count:$row_count,status:$status,transport:$transport}' >"$tmp_terminal"||{ rm -f "$tmp_terminal";return 1; };chmod 0600 "$tmp_terminal"||{ rm -f "$tmp_terminal";return 1; };mv "$tmp_terminal" "$worker_terminal_file"||{ rm -f "$tmp_terminal";return 1; };worker_terminal_written=true; }
worker_cleanup(){ if [ -n "${active_timeout_pid:-}" ];then kill "$active_timeout_pid" 2>/dev/null||true;wait "$active_timeout_pid" 2>/dev/null||true;active_timeout_pid=;fi;[ -z "${worker_query_tmp:-}" ]||rm -f "$worker_query_tmp";worker_write_terminal; }
# shellcheck disable=SC2329 # Invoked by the worker's INT/TERM traps.
worker_signal(){ local rc=$1;worker_rc_class=cancelled;trap - EXIT INT TERM;worker_cleanup;exit "$rc"; }
worker_entry(){ local rc;active_timeout_pid=;worker_query_tmp=;worker_rc_class=failed;trap worker_cleanup EXIT;trap 'worker_signal 130' INT;trap 'worker_signal 143' TERM;if check_dns_matrix "$@";then rc=0;worker_rc_class=success;else rc=$?;worker_rc_class=failed;fi;trap - EXIT INT TERM;worker_cleanup;return "$rc"; }
cancel_workers(){ local pid;for pid in "${worker_pids[@]:-}";do kill "$pid" 2>/dev/null||true;done;for pid in "${worker_pids[@]:-}";do wait "$pid" 2>/dev/null||true;done;worker_pids=(); }
run_outage_workers(){
  local worker_ordinal index pid rc=0 file terminal best_effort_diagnostic=true;local -a core_resolvers=(system system 192.168.10.230 192.168.10.230) core_transports=(udp tcp udp tcp) diagnostic_resolvers=("$rdnss" "$rdnss") diagnostic_transports=(udp tcp) core_pids=()
  [[ ${outage_deadline:-} =~ ^[0-9]+$ ]] || return 1
  worker_pids=();worker_files=();diagnostic_pids=();diagnostic_files=();diagnostic_terminal_files=()
  for worker_ordinal in 01 02 03 04;do
    index=$((10#$worker_ordinal-1));file="$run_dir/core-worker-$worker_ordinal.rows";: >"$file";chmod 0600 "$file";worker_files+=("$file")
    (trap - EXIT INT TERM;worker_entry "$worker_ordinal" "${core_resolvers[$index]}" "${core_transports[$index]}" "$file" "$outage_nonce") & pid=$!;core_pids+=("$pid");worker_pids+=("$pid")
  done
  for worker_ordinal in 01 02;do
    index=$((10#$worker_ordinal-1));file="$run_dir/diagnostic-worker-$worker_ordinal.rows";: >"$file";chmod 0600 "$file";diagnostic_files+=("$file");terminal="$run_dir/diagnostic-terminal-$worker_ordinal.json";diagnostic_terminal_files+=("$terminal")
    (trap - EXIT INT TERM;worker_terminal_file=$terminal;worker_terminal_ordinal=$((10#$worker_ordinal));worker_terminal_resolver_label=gateway-rdnss;worker_terminal_transport=${diagnostic_transports[$index]};worker_rows_file=$file;worker_terminal_written=false;worker_entry "$worker_ordinal" "${diagnostic_resolvers[$index]}" "${diagnostic_transports[$index]}" "$file" "$outage_nonce") & pid=$!;diagnostic_pids+=("$pid");worker_pids+=("$pid")
  done
  for pid in "${core_pids[@]}";do if ! wait "$pid";then rc=1;cancel_workers;break;fi;done
  if [ "$rc" -eq 0 ]&&$best_effort_diagnostic;then
    for pid in "${diagnostic_pids[@]}";do kill "$pid" 2>/dev/null||true;done
    for pid in "${diagnostic_pids[@]}";do wait "$pid" 2>/dev/null||true;done
  fi
  for index in 0 1;do
    if [ ! -s "${diagnostic_terminal_files[$index]}" ];then
      worker_terminal_file=${diagnostic_terminal_files[$index]};worker_terminal_ordinal=$((index+1));worker_terminal_resolver_label=gateway-rdnss;worker_terminal_transport=${diagnostic_transports[$index]};worker_rows_file=${diagnostic_files[$index]};worker_terminal_written=false;worker_rc_class=cancelled
      worker_write_terminal || true
    fi
  done
  worker_pids=();return "$rc"
}
append_postrestore_matrix(){ local ordinal=$1 resolver=$2 transport=$3 recovery_deadline=$4 file nonce;nonce=$(od -An -N16 -tx1 /dev/urandom|tr -d ' \n') || return 1;file=$(mktemp "$run_dir/.postrestore.XXXXXX");chmod 0600 "$file";check_dns_matrix "$ordinal" "$resolver" "$transport" "$file" "$nonce" || { rm -f "$file";return 1; };postrestore_evidence+="$(<"$file")"$'\n';rm -f "$file"; }
postrestore_identity() {
  local post nonmutable_before nonmutable_after mutable_before mutable_after
  recovery_capture "$observer" "$namespace" "$client_interface" "$remote_ip" "$bound" "$known_hosts" "$rdisc6" "$client" "$callback" || return 1;post=$REPLY
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
  local resolver transport filtered duration
  for resolver in "$rdnss" 192.168.10.210 192.168.10.230;do for transport in udp tcp;do append_postrestore_matrix 00 "$resolver" "$transport" "$recovery_deadline" || return 1;done;done
  recovery_run sudo -n ip netns exec "$namespace" getent ahostsv4 discovery.homelab.pastelariadev.com >/dev/null || return 1
  duration=$(deadline_duration "$recovery_deadline") || return 1;filtered=$(timeout "$duration" sudo -n ip netns exec "$namespace" dig +time=2 +tries=1 @192.168.10.210 doubleclick.net A) || return 1
  grep -Eq '0\.0\.0\.0|status: NXDOMAIN' <<<"$filtered" || return 1
  exporter_metrics_ready "$recovery_deadline" || return 1
  recovery_run "${ssh_command[@]}" "curl -kfsS --max-time 5 --resolve grafana.homelab.pastelariadev.com:443:127.0.0.1 -H 'Host: grafana.homelab.pastelariadev.com' https://grafana.homelab.pastelariadev.com/ >/dev/null" || return 1
  duration=$(deadline_duration "$recovery_deadline") || return 1;timeout "$duration" sudo -n ip netns exec "$namespace" dig +time=2 +tries=1 @192.168.10.210 k8s.pastelariadev.com A|grep -q 'status: NOERROR' || return 1
}
exporter_metrics_ready() {
  local recovery_deadline=$1 attempt now remaining duration warmup_deadline capture_file output rc expected
  expected=$'adguard_avg_processing_time_seconds=true\nadguard_queries=true\nadguard_queries_blocked=true\nrequired_family_count=3'
  now=$(date +%s%3N);warmup_deadline=$((now+60000));[ "$warmup_deadline" -le "$recovery_deadline" ] || warmup_deadline=$recovery_deadline
  for attempt in {1..60};do
    now=$(date +%s%3N);remaining=$((warmup_deadline-now));[ "$remaining" -gt 0 ] || return 1
    duration=$(timeout_duration "$remaining") || return 1
    capture_file=$(mktemp "$run_dir/.exporter-families.XXXXXX") || return 1
    chmod 0600 "$capture_file" || { rm -f "$capture_file" || true;return 1; }
    output=;rc=1
    if timeout "$duration" "${ssh_command[@]}" "sudo -n discovery-stateful-adguard-inventory exporter-families" >"$capture_file";then rc=0;else rc=$?;fi
    if ! output=$(<"$capture_file");then rm -f "$capture_file" || true;return 1;fi
    rm -f "$capture_file" || return 1
    if [ "$rc" -eq 0 ]&&[ "$output" = "$expected" ];then return 0;fi
    [ "$attempt" -eq 60 ] || deadline_sleep "$warmup_deadline" 1000 || return 1
  done
  return 1
}
freeze_outage_evidence() {
  local file diagnostic_hash_evidence terminal_count complete_terminal_count
  if [ -z "${frozen_outage_results_sha256:-}" ];then
    outage_evidence=;for file in "${worker_files[@]:-}";do [ -f "$file" ]&&outage_evidence+="$(<"$file")"$'\n';done
    outage_evidence=$(printf %s "$outage_evidence"|LC_ALL=C sort -s -t: -k1,1n -k2,2n)
    core_evidence_rows=$(printf '%s\n' "$outage_evidence"|sed '/^$/d'|wc -l);core_evidence_status=partial
    partial_outage_results_sha256=$(printf '%s\n' "$outage_evidence"|sha256sum|cut -d' ' -f1)
    if $outage_complete&&[ "$core_evidence_rows" -eq 24 ];then frozen_outage_results_sha256=$partial_outage_results_sha256;core_evidence_status=complete;fi
    diagnostic_evidence=;for file in "${diagnostic_files[@]:-}";do [ -f "$file" ]&&diagnostic_evidence+="$(<"$file")"$'\n';done
    diagnostic_evidence=$(printf %s "$diagnostic_evidence"|LC_ALL=C sort -s -t: -k1,1n -k2,2n)
    diagnostic_hash_evidence=$diagnostic_evidence;terminal_count=0;complete_terminal_count=0
    for file in "${diagnostic_terminal_files[@]:-}";do if [ -s "$file" ];then diagnostic_hash_evidence+="$(jq -cS . "$file")"$'\n';terminal_count=$((terminal_count+1));[ "$(jq -r .status "$file")" = complete ]&&complete_terminal_count=$((complete_terminal_count+1));fi;done
    diagnostic_evidence_rows=$(printf '%s\n' "$diagnostic_evidence"|sed '/^$/d'|wc -l);diagnostic_evidence_status=unavailable
    partial_diagnostic_results_sha256=$(printf '%s\n' "$diagnostic_hash_evidence"|sha256sum|cut -d' ' -f1)
    if [ "$terminal_count" -gt 0 ]||[ "$diagnostic_evidence_rows" -gt 0 ];then diagnostic_evidence_status=partial;fi
    if [ "$terminal_count" -eq 2 ]&&[ "$complete_terminal_count" -eq 2 ]&&[ "$diagnostic_evidence_rows" -eq 12 ];then frozen_diagnostic_results_sha256=$partial_diagnostic_results_sha256;diagnostic_evidence_status=complete;fi
  fi
}
recover() {
  local original=$? ok=false state attempt postrestore_rc=0 recovery_deadline
  original_failure_rc=$original;recovery_failed=false
  if [[ ${outage_start:-} =~ ^[0-9]+$ ]];then elapsed=$(($(date +%s%3N)-outage_start));fi
  cancel_workers;freeze_outage_evidence
  trap - EXIT INT TERM;enforce_deadline=false
  recovery_deadline=$(($(date +%s%3N)+120000))
  if $mutated;then
    for attempt in 1 2 3;do
      [ "$(date +%s%3N)" -lt "$recovery_deadline" ] || break
      record recovery-attempt "$attempt"
      recovery_run "${ssh_command[@]}" "docker start $adguard_id" >/dev/null 2>&1 || { record recovery-outcome start-adguard-failed;continue; }
      state="";for _ in {1..30};do recovery_capture "${ssh_command[@]}" "docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' $adguard_id" 2>/dev/null||break;state=$REPLY;[ "$state" = healthy ]&&break;deadline_sleep "$recovery_deadline" 1000||break;done
      [ "$state" = healthy ] || { record recovery-outcome health-failed;continue; }
      recovery_run "${ssh_command[@]}" "docker start $exporter_id" >/dev/null 2>&1 || { record recovery-outcome start-exporter-failed;continue; }
      exporter_metrics_ready "$recovery_deadline" || { record recovery-outcome exporter-readiness-failed;break; }
      postrestore_status=partial
      postrestore_identity || { postrestore_status=failed;record recovery-outcome identity-failed;continue; }
      record recovery-outcome restored;ok=true;break
    done
    if ! $ok;then recovery_failed=true;original=1;fi
    if $ok;then
      record postrestore-checks started
      postrestore_status=partial;postrestore_operational || postrestore_rc=$?
      if [ "$postrestore_rc" -eq 0 ];then postrestore_status=complete;record postrestore-checks passed;else postrestore_status=failed;record postrestore-checks failed;recovery_failed=true;original=1;fi
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
record stopped-gate passed
outage_nonce=$(od -An -N16 -tx1 /dev/urandom|tr -d ' \n') || exit 1;[[ $outage_nonce =~ ^[0-9a-f]{32}$ ]];outage_nonce_sha256=$(printf %s "$outage_nonce"|sha256sum|cut -d' ' -f1)
record failover-probe started;record gateway-diagnostic started
run_outage_workers
[ "$(cat "${worker_files[@]}"|wc -l)" -eq 24 ]
deadline_check;elapsed=$(($(date +%s%3N)-outage_start))
outage_complete=true;record failover-probe passed;record gateway-diagnostic captured;emit=true;record outage-proof passed;trap - EXIT INT TERM;recover
