#!/usr/bin/env bash
# Prepare/cleanup a persistent generic DHCP namespace for the P3 outage drill.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "root required" >&2;exit 2; }
command -v jq >/dev/null || exit 2
mode=${1:-};namespace=${2:-}
[[ $namespace =~ ^p3-dhcp-[a-zA-Z0-9_.-]+$ ]] || exit 2
netns_etc=/etc/netns/$namespace
state_dir=/run/p3-adguard-outage/$namespace
parent_addresses(){ ip -j address show dev "$1"|jq -cS 'map({ifname,address,mtu,flags:(.flags|sort),addr_info:([.addr_info[]|{family,local,prefixlen,scope,label}]|sort_by(.family,.local,.prefixlen,.scope,.label))})'; }
parent_routes(){ ip -j route show table all dev "$1"|jq -cS 'map(del(.expires,.cache,.used,.lastuse)|if .nexthops then .nexthops|=sort_by(.dev,.gateway,.weight) else . end)|sort_by(.table//"main",.dst//"default",.gateway//"",.prefsrc//"",.protocol//"")'; }
if [ "$mode" = cleanup ];then
  [ -d "$state_dir" ] || exit 1;parent=$(<"$state_dir/parent")
  ip netns delete "$namespace" 2>/dev/null||true;rm -rf "$netns_etc"
  ip netns list|awk '{print $1}'|grep -Fxq "$namespace"&&exit 1
  [ "$(parent_addresses "$parent")" = "$(<"$state_dir/address.json")" ]
  [ "$(parent_routes "$parent")" = "$(<"$state_dir/routes.json")" ]
  [ "$(cat "/sys/class/net/$parent/carrier")" = "$(<"$state_dir/carrier")" ]
  rm -rf "$state_dir";exit 0
fi
if [ "$mode" = prepare ];then [ "$#" -eq 6 ] || { echo "usage: $0 prepare NAMESPACE WIRED_INTERFACE UDHCPC CALLBACK RDISC6 | cleanup NAMESPACE" >&2;exit 2; };else exit 2;fi
parent=$3;udhcpc=$4;callback=$5;rdisc6=$6;probe="p3d${RANDOM}";created=false;capture=;tmp=;ra_tmp=
[ ! -e "$netns_etc" ] && [ ! -e "$state_dir" ] && ! ip netns list|awk '{print $1}'|grep -Fxq "$namespace" || exit 1
[ -x "$udhcpc" ] && [ -x "$callback" ] && [ -x "$rdisc6" ] && [ "$(stat -c %u "$callback")" = 0 ] || exit 1
callback_mode=$(stat -c %a "$callback");(( (8#$callback_mode & 8#022) == 0 )) || exit 1
cleanup_failure(){ rc=$?;[ -n "$capture" ]&&rm -f "$capture";[ -n "$tmp" ]&&rm -f "$tmp";[ -n "$ra_tmp" ]&&rm -f "$ra_tmp";if [ "$rc" -ne 0 ];then $created&&ip netns delete "$namespace" 2>/dev/null||true;rm -rf "$netns_etc" "$state_dir";fi;exit "$rc";};trap cleanup_failure EXIT
case $parent in *br*|*tun*|*tap*|*wg*|*ts*|*nb*) exit 1;;esac
[ "$(cat "/sys/class/net/$parent/carrier")" = 1 ] && [ ! -e "/sys/class/net/$parent/wireless" ]
route=$(ip -j -4 route get 192.168.10.1);[ "$(jq -r 'length==1 and .[0].dst=="192.168.10.1" and .[0].dev==$parent' --arg parent "$parent" <<<"$route")" = true ]
install -d -m 0700 "$state_dir";printf '%s\n' "$parent" >"$state_dir/parent";parent_addresses "$parent" >"$state_dir/address.json";parent_routes "$parent" >"$state_dir/routes.json";cat "/sys/class/net/$parent/carrier" >"$state_dir/carrier";chmod 0600 "$state_dir"/*
ip netns add "$namespace";created=true
mac=$(printf '02:%02x:%02x:%02x:%02x:%02x' $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)))
ip link add link "$parent" name "$probe" address "$mac" type macvlan mode bridge;ip link set "$probe" netns "$namespace";ip -n "$namespace" link set lo up;ip -n "$namespace" link set "$probe" up
iid=$(printf '%s' "$namespace:$probe:$RANDOM:$RANDOM:$(date +%s%N)"|sha256sum|cut -c1-16);link_local="fe80::${iid:0:4}:${iid:4:4}:${iid:8:4}:${iid:12:4}"
ip -n "$namespace" -6 address add "$link_local/64" dev "$probe" nodad
[ "$(ip -j -n "$namespace" -6 address show dev "$probe" scope link|jq -r --arg address "$link_local" '[.[].addr_info[]|select(.family=="inet6" and .scope=="link" and .local==$address)]|length')" -eq 1 ]
ra_tmp=$(mktemp);timeout 12 ip netns exec "$namespace" "$rdisc6" -1 "$probe" >"$ra_tmp"
mapfile -t rdnss < <(sed -n 's/^[[:space:]]*Recursive DNS server[[:space:]]*:[[:space:]]*//p' "$ra_tmp")
[ "${#rdnss[@]}" -eq 1 ] && [[ ${rdnss[0]} == *:* ]]
capture=$(mktemp);P3_DHCP_CAPTURE=$capture timeout 25 ip netns exec "$namespace" "$udhcpc" -f -n -q -T 3 -t 4 -A 2 -O dns -i "$probe" -s "$callback" >/dev/null
record=$(<"$capture");[[ $record =~ ^event=(bound|renew)[[:space:]]dns=192\.168\.10\.210[[:space:]]192\.168\.10\.230$ ]]
install -d -m 0700 "$netns_etc";tmp=$(mktemp "$netns_etc/resolv.conf.tmp.XXXXXX");chmod 0600 "$tmp";printf 'nameserver %s\nnameserver 192.168.10.210\nnameserver 192.168.10.230\noptions timeout:2 attempts:1\n' "${rdnss[0]}" >"$tmp";mv "$tmp" "$netns_etc/resolv.conf";tmp=
mapfile -t links < <(ip -n "$namespace" -o link show|awk -F': ' 'NF>=2{print $2}'|sed 's/@.*//');[ "${links[*]}" = "lo $probe" ]
rm -f "$capture" "$ra_tmp";capture=;ra_tmp=;trap - EXIT;jq -cnS --arg namespace "$namespace" --arg interface "$probe" '{interface:$interface,namespace:$namespace,status:"prepared",version:1}'
