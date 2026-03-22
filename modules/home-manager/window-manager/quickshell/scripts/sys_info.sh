#!/usr/bin/env bash
# System info script for quickshell bar pills
# Each mode outputs a single line of plain text

case "$1" in
    wifi-ssid)
        nmcli -t -f active,ssid dev wifi | grep '^yes:' | cut -d: -f2
        ;;
    wifi-strength)
        nmcli -t -f active,signal dev wifi | grep '^yes:' | cut -d: -f2
        ;;
    wifi-status)
        nmcli -t -f WIFI general | head -1
        ;;
    bt-status)
        bluetoothctl show | grep -q "Powered: yes" && echo "on" || echo "off"
        ;;
    bt-device)
        bluetoothctl devices Connected | head -1 | cut -d' ' -f3-
        ;;
    volume)
        wpctl get-volume @DEFAULT_AUDIO_SINK@ | awk '{printf "%.0f\n", $2 * 100}'
        ;;
    volume-muted)
        wpctl get-volume @DEFAULT_AUDIO_SINK@ | grep -q MUTED && echo "true" || echo "false"
        ;;
    battery-percent)
        cat /sys/class/power_supply/BAT*/capacity 2>/dev/null || echo ""
        ;;
    battery-status)
        cat /sys/class/power_supply/BAT*/status 2>/dev/null || echo ""
        ;;
    brightness)
        brightnessctl -m | cut -d, -f4 | tr -d '%'
        ;;
    kb-layout)
        layout=$(hyprctl devices -j | jq -r '.keyboards[] | select(.main == true) .active_keymap' 2>/dev/null | head -c 2 | tr '[:lower:]' '[:upper:]')
        echo "$layout"
        ;;
    uptime)
        uptime -p | sed 's/up //'
        ;;
    cpu)
        awk '/^cpu /{printf "%.0f\n", 100 - ($5 * 100 / ($2+$3+$4+$5+$6+$7+$8))}' /proc/stat
        ;;
    memory)
        free | awk '/^Mem:/{printf "%.0f\n", $3/$2 * 100}'
        ;;
    temperature)
        temp=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null)
        if [ -n "$temp" ]; then
            echo $((temp / 1000))
        fi
        ;;
    disk)
        df / | awk 'NR==2{gsub(/%/,"",$5); print $5}'
        ;;
    mic-muted)
        wpctl get-volume @DEFAULT_AUDIO_SOURCE@ | grep -q MUTED && echo "true" || echo "false"
        ;;
    *)
        echo "Usage: $0 {wifi-ssid|wifi-strength|wifi-status|bt-status|bt-device|volume|volume-muted|battery-percent|battery-status|brightness|kb-layout|uptime|cpu|memory|temperature|disk|mic-muted}"
        exit 1
        ;;
esac
