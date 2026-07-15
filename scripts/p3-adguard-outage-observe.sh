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
mapfile -t links < <(sudo -n ip -n "$namespace" -o link show|awk -F': ' 'NF>=2{print $2}'|sed 's/@.*//')
[ "${links[*]}" = "lo $interface" ]
# shellcheck disable=SC2016
mapfile -t resolvers < <(sudo -n ip netns exec "$namespace" awk '/^nameserver[[:space:]]/{print $2}' /etc/resolv.conf)
[ "${resolvers[*]}" = "192.168.10.210 192.168.10.230" ]
mapfile -t ipv6_default < <(sudo -n ip -n "$namespace" -6 route show default)
[ "${#ipv6_default[@]}" -eq 0 ];for resolver in "${resolvers[@]}";do [[ $resolver != *:* ]] || exit 1;done
ra_file=$(mktemp);cleanup(){ rm -f "$ra_file"; };trap cleanup EXIT INT TERM
set +e
timeout "$(awk "BEGIN{print $bound/1000}")" sudo -n ip netns exec "$namespace" "$rdisc6" -1 "$interface" >"$ra_file" 2>&1
ra_rc=$?
set -e
if [ "$ra_rc" -ne 2 ] || ! grep -Fqi 'No response' "$ra_file" || grep -Eqi 'router advertisement|rdnss|recursive dns' "$ra_file";then exit 1;fi
ssh_opts=(-p 2222 -o BatchMode=yes -o ConnectTimeout=8 -o ConnectionAttempts=1 -o StrictHostKeyChecking=yes -o UserKnownHostsFile="$known_hosts")
remote=(ssh "${ssh_opts[@]}" "erik@$remote_ip")
"${remote[@]}" "docker info >/dev/null"
mapfile -t project_ids < <("${remote[@]}" "docker ps -aq --filter label=com.docker.compose.project=networking")
[ "${#project_ids[@]}" -eq 5 ];if printf '%s\n' "${project_ids[@]}"|grep -Evq '^[0-9a-f]{64}$';then exit 1;fi
[ "$(printf '%s\n' "${project_ids[@]}"|sort -u|wc -l)" -eq 5 ]
printf -v inspect_command 'docker inspect';for id in "${project_ids[@]}";do printf -v inspect_command '%s %s' "$inspect_command" "$id";done
containers=$("${remote[@]}" "$inspect_command" | jq -cS '
  [.[]|{id:.Id,name:(.Name|ltrimstr("/")),project:.Config.Labels["com.docker.compose.project"],service:.Config.Labels["com.docker.compose.service"],working_dir:.Config.Labels["com.docker.compose.project.working_dir"],image_id:.Image,image_ref:.Config.Image,state:.State.Status,exit_code:.State.ExitCode,health:(.State.Health.Status//null),restart_count:.RestartCount,restart_policy:.HostConfig.RestartPolicy,networks:([.NetworkSettings.Networks|to_entries[]|{name:.key,aliases:(.value.Aliases//[]|sort),ip_address:.value.IPAddress,global_ipv6_address:.value.GlobalIPv6Address}]|sort_by(.name)),mounts:([.Mounts[]|{type:.Type,name:(.Name//null),source:.Source,destination:.Destination,driver:(.Driver//null),mode:.Mode,rw:.RW,propagation:.Propagation}]|sort_by(.destination))}]|sort_by(.name)')
[ "$(printf '%s\n' "${project_ids[@]}"|sort)" = "$(jq -r '.[].id' <<<"$containers"|sort)" ]
jq -e 'length==5 and ([.[].name]|sort)==["adguard","adguard-exporter","k8s-apiserver","swag","swag-init"] and all(.[];(.id|test("^[0-9a-f]{64}$")) and (.image_id|test("^sha256:[0-9a-f]{64}$")) and (.image_ref|type=="string" and length>0) and (.restart_count|type=="number") and (.restart_policy|type=="object") and (.networks|type=="array") and (.mounts|type=="array")) and all(.[];.project=="networking" and .service==.name and .working_dir=="/home/erik/servarr/machines/discovery") and all(.[]|select(.name!="swag-init");.state=="running") and (map(select(.name=="swag-init"))[0]|.state=="exited" and .exit_code==0)' >/dev/null <<<"$containers"
jq -cnS --arg namespace "$namespace" --arg interface "$interface" --arg ip "$remote_ip" --argjson bound "$bound" --argjson containers "$containers" '{client:{interface:$interface,namespace:$namespace,overlays:[],persistent_macvlan:true},containers:$containers,dhcp_dns:["192.168.10.210","192.168.10.230"],failover_bound_ms:$bound,ipv6:{default_routes:[],rdnss:[],ra_probe:"bounded-no-ra"},remote:{ip:$ip,recovery_by_ip:true},version:3}'
