#!/usr/bin/env bash
# Rootless, read-only observation for an already-persistent generic DHCP namespace.
set -euo pipefail
[ "$#" -eq 8 ] || { echo "usage: $0 NAMESPACE INTERFACE DISCOVERY_IP BOUND_MS KNOWN_HOSTS RDISC6 CLIENT CALLBACK" >&2;exit 2; }
namespace=$1;interface=$2;remote_ip=$3;bound=$4;known_hosts=$5;rdisc6=$6;client=$7;callback=$8
[[ $namespace =~ ^[a-zA-Z0-9_.-]+$ && $interface =~ ^[a-zA-Z0-9_.-]+$ && $remote_ip =~ ^[0-9]+(\.[0-9]+){3}$ && $bound =~ ^[0-9]+$ ]] || exit 2
[ -f "$known_hosts" ] && [ ! -L "$known_hosts" ] && [ "$(stat -c %u "$known_hosts")" = "$(id -u)" ] && [ "$(stat -c %a "$known_hosts")" = 400 ] || exit 2
[ -x "$rdisc6" ] && [ -x "$client" ] && [ -x "$callback" ] || exit 2
sudo -n ip netns exec "$namespace" true
sudo -n ip netns list|awk '{print $1}'|grep -Fxq "$namespace"
sudo -n ip -n "$namespace" -d link show dev "$interface"|grep -qw macvlan
mapfile -t links < <(sudo -n ip -n "$namespace" -o link show|awk -F': ' 'NF>=2{print $2}'|sed 's/@.*//');[ "${links[*]}" = "lo $interface" ]
# The prepare step owns this namespace-local file; reject comments, extra
# directives, search domains, or reordered fallbacks rather than filtering them.
mapfile -t resolver_lines < <(sudo -n ip netns exec "$namespace" cat /etc/resolv.conf)
[ "${#resolver_lines[@]}" -eq 4 ];[[ ${resolver_lines[0]} =~ ^nameserver[[:space:]]+([^[:space:]]+)$ ]];rdnss=${BASH_REMATCH[1]}
[ "${resolver_lines[1]}" = "nameserver 192.168.10.210" ] && [ "${resolver_lines[2]}" = "nameserver 192.168.10.230" ] && [ "${resolver_lines[3]}" = "options timeout:2 attempts:1" ]
[[ $rdnss == *:* ]]
link_local=$(sudo -n ip -j -n "$namespace" -6 address show dev "$interface" scope link);jq -e '[.[].addr_info[]|select(.family=="inet6" and .scope=="link" and (.local|test("^fe80:")))]|length==1' >/dev/null <<<"$link_local"
ra_file=$(mktemp);cleanup(){ rm -f "$ra_file"; };trap cleanup EXIT INT TERM
timeout "$(awk "BEGIN{print $bound/1000}")" sudo -n ip netns exec "$namespace" "$rdisc6" -1 "$interface" >"$ra_file"
mapfile -t routers < <(sed -n 's/^[[:space:]]*from[[:space:]]*//p' "$ra_file");mapfile -t prefixes < <(sed -n 's/^[[:space:]]*Prefix[[:space:]]*:[[:space:]]*//p' "$ra_file");mapfile -t advertised_dns < <(sed -n 's/^[[:space:]]*Recursive DNS server[[:space:]]*:[[:space:]]*//p' "$ra_file")
mapfile -t router_lifetimes < <(sed -n 's/^[[:space:]]*Router lifetime[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$ra_file");mapfile -t dns_lifetimes < <(sed -n 's/^[[:space:]]*DNS server lifetime[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$ra_file")
if [ "${#routers[@]}" -ne 1 ] || [ "${#prefixes[@]}" -ne 1 ] || [ "${#advertised_dns[@]}" -ne 1 ] || [ "${#router_lifetimes[@]}" -ne 1 ] || [ "${#dns_lifetimes[@]}" -ne 1 ];then exit 1;fi
if [ "${advertised_dns[0]}" != "$rdnss" ] || [ "${router_lifetimes[0]}" -le 0 ] || [ "${dns_lifetimes[0]}" -le 0 ] || [[ ${routers[0]} != fe80:* ]] || [[ ${prefixes[0]} != */64 ]];then exit 1;fi
default_route=$(sudo -n ip -j -n "$namespace" -6 route show default|jq -cS --arg router "${routers[0]}" --arg interface "$interface" '[.[]|select(.dst=="default" and .gateway==$router and .dev==$interface)|{dev,dst,gateway,protocol}]')
[ "$(jq length <<<"$default_route")" -eq 1 ]
nonce=$(od -An -N16 -tx1 /dev/urandom|tr -d ' \n');evidence=;classifications=;qnames=
probe_matrix() {
  local label=$1 resolver=$2 transport=$3 name type _expected_status contract out answers rc dns_status count_class classification qname_sha;local -a args=()
  [ "$resolver" != system ] && args+=(@"$resolver");[ "$transport" = tcp ] && args+=(+tcp)
  while read -r name type _expected_status contract;do
    name=${name//\{nonce\}/$nonce};if out=$(sudo -n ip netns exec "$namespace" dig "${args[@]}" +time=2 +tries=1 "$name" "$type");then rc=0;else rc=$?;fi
    [ "$rc" -eq 0 ];dns_status=$(sed -n 's/.*status: \([^,]*\).*/\1/p' <<<"$out"|head -1);answers=$(sed -n 's/.*ANSWER: \([0-9]*\).*/\1/p' <<<"$out"|head -1);[[ $answers =~ ^[0-9]+$ ]]
    if [ "$answers" -eq 0 ];then count_class=zero;else count_class=positive;fi
    case $contract in
      fleet-a) [ "$dns_status" = NOERROR ]&&[ "$count_class" = positive ]&&grep -q '192\.168\.10\.210' <<<"$out";classification="fleet-a";;
      fleet-aaaa) [ "$dns_status" = NOERROR ]&&[ "$count_class" = zero ];classification="nodata";;
      external) [ "$dns_status" = NOERROR ]&&[ "$count_class" = positive ];classification="external-positive";;
      nxdomain) [ "$dns_status" = NXDOMAIN ]&&[ "$count_class" = zero ];classification="nxdomain";;
      # Filtering accepts status: NXDOMAIN with zero answers or NOERROR with 0.0.0.0.
      filtered) if [ "$dns_status" = NXDOMAIN ]&&[ "$count_class" = zero ];then classification="filtered-nxdomain";elif [ "$dns_status" = NOERROR ]&&grep -q '0\.0\.0\.0' <<<"$out";then classification="filtered-null";else return 1;fi;;
    esac
    qname_sha=$(printf %s "$name"|sha256sum|cut -d' ' -f1);qnames+="$qname_sha\n";classifications+="$label:$transport:$type:$contract:observed_rc=$rc:observed_status=$dns_status:answer_count_class=$count_class:answer_classification=$classification\n";evidence+="$label:$transport:$type:$contract:observed_rc=$rc:observed_status=$dns_status:answer_count_class=$count_class:answer_classification=$classification:qname_sha256=$qname_sha\n"
  done <<'EOF'
{nonce}.homelab.pastelariadev.com A NOERROR fleet-a
{nonce}.homelab.pastelariadev.com AAAA NOERROR fleet-aaaa
{nonce}.1-1-1-1.sslip.io A NOERROR external
{nonce}.2606-4700-4700--1111.sslip.io AAAA NOERROR external
{nonce}.invalid A NXDOMAIN nxdomain
{nonce}.doubleclick.net A ANY filtered
EOF
}
for transport in udp tcp;do probe_matrix gateway "$rdnss" "$transport";probe_matrix adguard 192.168.10.210 "$transport";probe_matrix kepler 192.168.10.230 "$transport";probe_matrix system system "$transport";done
ssh_opts=(-p 2222 -o BatchMode=yes -o ConnectTimeout=8 -o ConnectionAttempts=1 -o StrictHostKeyChecking=yes -o UserKnownHostsFile="$known_hosts" -o GlobalKnownHostsFile=/dev/null);remote=(ssh "${ssh_opts[@]}" "erik@$remote_ip")
"${remote[@]}" "docker info >/dev/null";mapfile -t project_ids < <("${remote[@]}" "docker ps -aq --filter label=com.docker.compose.project=networking")
[ "${#project_ids[@]}" -eq 5 ];if printf '%s\n' "${project_ids[@]}"|grep -Evq '^[0-9a-f]{64}$';then exit 1;fi;[ "$(printf '%s\n' "${project_ids[@]}"|sort -u|wc -l)" -eq 5 ]
printf -v inspect_command 'docker inspect';for id in "${project_ids[@]}";do printf -v inspect_command '%s %s' "$inspect_command" "$id";done
containers=$("${remote[@]}" "$inspect_command" | jq -cS '[.[]|{id:.Id,name:(.Name|ltrimstr("/")),project:.Config.Labels["com.docker.compose.project"],service:.Config.Labels["com.docker.compose.service"],working_dir:.Config.Labels["com.docker.compose.project.working_dir"],image_id:.Image,image_ref:.Config.Image,state:.State.Status,exit_code:.State.ExitCode,health:(.State.Health.Status//null),restart_count:.RestartCount,restart_policy:.HostConfig.RestartPolicy,networks:([.NetworkSettings.Networks|to_entries[]|{name:.key,aliases:(.value.Aliases//[]|sort),ip_address:.value.IPAddress,global_ipv6_address:.value.GlobalIPv6Address}]|sort_by(.name)),mounts:([.Mounts[]|{type:.Type,name:(.Name//null),source:.Source,destination:.Destination,driver:(.Driver//null),mode:.Mode,rw:.RW,propagation:.Propagation}]|sort_by(.destination))}]|sort_by(.name)')
[ "$(printf '%s\n' "${project_ids[@]}"|sort)" = "$(jq -r '.[].id' <<<"$containers"|sort)" ];jq -e 'length==5 and ([.[].name]|sort)==["adguard","adguard-exporter","k8s-apiserver","swag","swag-init"] and all(.[];(.id|test("^[0-9a-f]{64}$")) and (.image_id|test("^sha256:[0-9a-f]{64}$")) and (.image_ref|type=="string" and length>0) and (.restart_count|type=="number") and (.restart_policy|type=="object") and (.networks|type=="array") and (.mounts|type=="array")) and all(.[];.project=="networking" and .service==.name and .working_dir=="/home/erik/servarr/machines/discovery") and all(.[]|select(.name!="swag-init");.state=="running") and (map(select(.name=="swag-init"))[0]|.state=="exited" and .exit_code==0)' >/dev/null <<<"$containers"
nonce_sha=$(printf %s "$nonce"|sha256sum|cut -d' ' -f1);evidence_sha=$(printf %b "$evidence"|sha256sum|cut -d' ' -f1);classification_sha=$(printf %b "$classifications"|sha256sum|cut -d' ' -f1);qnames_sha=$(printf %b "$qnames"|sha256sum|cut -d' ' -f1)
jq -cnS --arg namespace "$namespace" --arg interface "$interface" --arg ip "$remote_ip" --argjson bound "$bound" --argjson containers "$containers" --arg router "${routers[0]}" --arg prefix "${prefixes[0]}" --arg rdnss "$rdnss" --argjson default_route "$default_route" --arg nonce_sha "$nonce_sha" --arg evidence_sha "$evidence_sha" --arg classification_sha "$classification_sha" --arg qnames_sha "$qnames_sha" '{client:{interface:$interface,namespace:$namespace,overlays:[],persistent_macvlan:true},containers:$containers,failover_bound_ms:$bound,ipv6:{default_route:$default_route[0],prefix:$prefix,rdnss:$rdnss,rdnss_lifetime:"positive",router:$router,router_lifetime:"positive"},probe_contract:{filter_template:"{nonce}.doubleclick.net A",fleet_templates:["{nonce}.homelab.pastelariadev.com A","{nonce}.homelab.pastelariadev.com AAAA"],negative_template:"{nonce}.invalid A",public_templates:["{nonce}.1-1-1-1.sslip.io A","{nonce}.2606-4700-4700--1111.sslip.io AAAA"],resolvers:["gateway","adguard","kepler","system"],transports:["udp","tcp"]},probe_evidence:{classifications_sha256:$classification_sha,nonce_sha256:$nonce_sha,qnames_sha256:$qnames_sha,results_sha256:$evidence_sha},remote:{ip:$ip,recovery_by_ip:true},resolvers:{nameservers:[$rdnss,"192.168.10.210","192.168.10.230"],options:["timeout:2","attempts:1"]},version:3}'
