#!/usr/bin/env bash
# Tailscale's forwarded-packet mark triggers SNAT even after Docker DNAT.
# Clear only that bit for Discovery-published HTTPS, after ACLs/routing and
# before NAT. Other subnet traffic must retain the normal Tailscale SNAT.
set -euo pipefail
action=$1
shift
case "$action" in add|remove) ;; *) exit 2 ;; esac
for address in "$@"; do
  rule=(-o 'br+' -s 100.64.0.0/10 -p tcp --dport 443
    -m mark --mark 0x40000/0xff0000
    -m conntrack --ctstate DNAT --ctdir ORIGINAL --ctorigdst "$address" --ctorigdstport 443
    -j MARK --set-xmark 0/0x40000)
  if iptables -w -t mangle -C POSTROUTING "${rule[@]}" 2>/dev/null; then
    if [ "$action" = remove ]; then iptables -w -t mangle -D POSTROUTING "${rule[@]}"; fi
  elif [ "$action" = add ]; then
    iptables -w -t mangle -A POSTROUTING "${rule[@]}"
  fi
done
