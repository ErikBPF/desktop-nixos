#!/usr/bin/env bash
# Ephemeral DHCP option-6 and resolver proof for a generic wired client.
set -euo pipefail

[ "$#" -eq 3 ] || { echo "usage: $0 WIRED_INTERFACE UDHCPC_BINARY UDHCPC_CALLBACK" >&2; exit 2; }
[ "$(id -u)" -eq 0 ] || { echo "root is required" >&2; exit 2; }
command -v jq >/dev/null || { echo "jq is required" >&2; exit 2; }
wired_interface=$1;udhcpc_binary=$2;udhcpc_callback=$3
sys_class_net=${P3_SYS_CLASS_NET:-/sys/class/net}
namespace="p3-dhcp-${RANDOM}-$$";probe_interface="p3d${RANDOM}"
temp_dir="";namespace_created=false
[[ $wired_interface =~ ^[a-zA-Z0-9_.:-]+$ ]] || { echo "invalid wired interface" >&2; exit 2; }
case $wired_interface in *br*|*tun*|*tap*|*wg*|*ts*|*nb*) echo "unsupported parent interface" >&2; exit 2;; esac
[ -x "$udhcpc_binary" ] && [ -x "$udhcpc_callback" ] || { echo "DHCP executable missing" >&2; exit 2; }
[ "$(stat -c %u "$udhcpc_callback")" = 0 ] || { echo "callback must be root-owned" >&2; exit 2; }
callback_mode=$(stat -c %a "$udhcpc_callback")
(( (8#$callback_mode & 8#022) == 0 )) || { echo "callback must not be group/world writable" >&2; exit 2; }
[ -r "$sys_class_net/$wired_interface/carrier" ] && [ "$(cat "$sys_class_net/$wired_interface/carrier")" = 1 ] || { echo "wired carrier absent" >&2; exit 1; }
[ ! -e "$sys_class_net/$wired_interface/wireless" ] || { echo "wireless parent rejected" >&2; exit 1; }
route_dev=$(ip -j -4 route get 192.168.10.1 | jq -er 'if length == 1 then .[0].dev else empty end')
[ "$route_dev" = "$wired_interface" ] || { echo "gateway route does not use exact parent" >&2; exit 1; }
parent_addresses() {
  ip -j address show dev "$wired_interface" | jq -cS '
    map({ifname,address,mtu,flags:(.flags|sort),addr_info:(
      [.addr_info[]|{family,local,prefixlen,scope,label}]|sort_by(.family,.local,.prefixlen,.scope,.label)
    )})'
}
parent_routes() {
  ip -j route show table all dev "$wired_interface" | jq -cS '
    map(del(.expires,.cache,.used,.lastuse)
      | if .nexthops then .nexthops |= sort_by(.dev,.gateway,.weight) else . end)
    | sort_by(.table//"main",.dst//"default",.gateway//"",.prefsrc//"",.protocol//"")'
}
before_addr=$(parent_addresses);before_routes=$(parent_routes);before_carrier=$(cat "$sys_class_net/$wired_interface/carrier")

cleanup() {
  rc=$?;trap - EXIT INT TERM
  $namespace_created && ip netns delete "$namespace" >/dev/null 2>&1 || true
  if ip netns list | awk '{print $1}' | grep -Fxq "$namespace"; then echo "namespace cleanup failed" >&2;rc=1;fi
  [ "$(parent_addresses)" = "$before_addr" ] || { echo "parent addresses changed" >&2;rc=1; }
  [ "$(parent_routes)" = "$before_routes" ] || { echo "parent routes changed" >&2;rc=1; }
  [ "$(cat "$sys_class_net/$wired_interface/carrier")" = "$before_carrier" ] || { echo "parent carrier changed" >&2;rc=1; }
  [ -z "$temp_dir" ] || rm -rf "$temp_dir"
  exit "$rc"
}
trap cleanup EXIT INT TERM
temp_dir=$(mktemp -d);chmod 0700 "$temp_dir";capture=$temp_dir/lease
mac=$(printf '02:%02x:%02x:%02x:%02x:%02x' $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)))
ip netns add "$namespace" >/dev/null;namespace_created=true
ip link add link "$wired_interface" name "$probe_interface" address "$mac" type macvlan mode bridge >/dev/null
ip link set "$probe_interface" netns "$namespace" >/dev/null
ip -n "$namespace" link set lo up >/dev/null;ip -n "$namespace" link set "$probe_interface" up >/dev/null
links=$(ip -n "$namespace" -o link show)
while IFS= read -r name;do case ${name%%@*} in lo|"$probe_interface");;*) echo "unexpected namespace interface" >&2;exit 1;;esac;done < <(printf '%s\n' "$links"|awk -F': ' 'NF>=2{print $2}')
P3_DHCP_CAPTURE=$capture timeout 25 ip netns exec "$namespace" "$udhcpc_binary" -f -n -q -T 3 -t 4 -A 2 -O dns -i "$probe_interface" -s "$udhcpc_callback" >/dev/null || { echo "DHCP lease acquisition failed" >&2;exit 1; }
mapfile -t records < "$capture";[ "${#records[@]}" -eq 1 ] || { echo "DHCP capture missing or ambiguous" >&2;exit 1; }
[[ ${records[0]} =~ ^event=(bound|renew)[[:space:]]dns=(.*)$ ]] || { echo "callback emitted invalid event" >&2;exit 1; }
read -r -a dns_servers <<<"${BASH_REMATCH[2]//,/ }"
[ "${dns_servers[*]}" = "192.168.10.210 192.168.10.230" ] || { echo "DHCP DNS option differs" >&2;exit 1; }
for server in "${dns_servers[@]}";do
  a=$(ip netns exec "$namespace" dig +time=2 +tries=1 @"$server" discovery.homelab.pastelariadev.com A);grep -q 'status: NOERROR' <<<"$a";grep -q '192.168.10.210' <<<"$a"
  tcp=$(ip netns exec "$namespace" dig +tcp +time=2 +tries=1 @"$server" discovery.homelab.pastelariadev.com A);grep -q 'status: NOERROR' <<<"$tcp";grep -q '192.168.10.210' <<<"$tcp"
  aaaa=$(ip netns exec "$namespace" dig +time=2 +tries=1 @"$server" discovery.homelab.pastelariadev.com AAAA);grep -q 'status: NOERROR' <<<"$aaaa";grep -q 'ANSWER: 0' <<<"$aaaa"
  wildcard=$(ip netns exec "$namespace" dig +time=2 +tries=1 @"$server" p3-arbitrary.homelab.pastelariadev.com A);grep -q 'status: NOERROR' <<<"$wildcard";grep -q '192.168.10.210' <<<"$wildcard"
  nx=$(ip netns exec "$namespace" dig +time=2 +tries=1 @"$server" p3-nonexistent.invalid A);grep -q 'status: NXDOMAIN' <<<"$nx"
done
printf 'dhcp_dns=%s,%s\n' "${dns_servers[0]}" "${dns_servers[1]}"
