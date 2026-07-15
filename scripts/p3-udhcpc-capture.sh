#!/usr/bin/env bash
# udhcpc callback: configure only its current namespace and capture option 6.
set -euo pipefail

event=${1:-}
case $event in
  deconfig)
    [ -n "${interface:-}" ] || exit 1
    ip address flush dev "$interface"
    exit 0
    ;;
  bound|renew) ;;
  *) exit 1 ;;
esac

capture=${P3_DHCP_CAPTURE:?};interface=${interface:?};address=${ip:?};mask=${subnet:?}
routers=${router:?};dns_servers=${dns:?}
valid_ipv4() {
  local value=$1 part
  [[ $value =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
  IFS=. read -r -a parts <<<"$value"
  for part in "${parts[@]}";do [[ $part =~ ^[0-9]+$ ]] && ((10#$part <= 255)) || return 1;done
}
valid_ipv4 "$address" && valid_ipv4 "$mask" || exit 1
read -r -a router_list <<<"$routers";[ "${#router_list[@]}" -eq 1 ] && valid_ipv4 "${router_list[0]}" || exit 1
read -r -a dns_list <<<"$dns_servers";[ "${#dns_list[@]}" -ge 1 ] || exit 1
for server in "${dns_list[@]}";do valid_ipv4 "$server" || exit 1;done

prefix=0;zero_seen=false
IFS=. read -r -a mask_parts <<<"$mask"
for part in "${mask_parts[@]}";do
  for ((bit=7;bit>=0;bit--));do
    if (( (10#$part >> bit) & 1 ));then $zero_seen && exit 1;((prefix+=1));else zero_seen=true;fi
  done
done

ip link set "$interface" up
ip address replace "$address/$prefix" dev "$interface"
ip route replace default via "${router_list[0]}" dev "$interface"
tmp=$(mktemp "${capture}.tmp.XXXXXX");trap 'rm -f "$tmp"' EXIT
chmod 0600 "$tmp"
printf 'event=%s dns=%s\n' "$event" "${dns_list[*]}" >"$tmp"
mv -f "$tmp" "$capture";trap - EXIT
