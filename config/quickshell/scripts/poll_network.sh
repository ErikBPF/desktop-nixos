#!/usr/bin/env bash
# Network info for popup — wifi networks + bluetooth devices

mode="${1:-wifi}"

if [ "$mode" = "wifi" ]; then
    # Current connection
    ssid=$(nmcli -t -f active,ssid dev wifi | grep '^yes:' | cut -d: -f2)
    echo "connected=$ssid"
    # Available networks (top 10 by signal)
    nmcli -t -f ssid,signal,security dev wifi list 2>/dev/null | head -10 | while IFS=: read -r name signal sec; do
        [ -z "$name" ] && continue
        echo "net=$name|$signal|$sec"
    done
elif [ "$mode" = "bt" ]; then
    # Connected devices
    bluetoothctl devices Connected 2>/dev/null | while read -r _ mac name; do
        echo "btconn=$name|$mac"
    done
    # Paired devices
    bluetoothctl devices Paired 2>/dev/null | while read -r _ mac name; do
        echo "btpaired=$name|$mac"
    done
fi
