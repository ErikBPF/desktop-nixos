#!/usr/bin/env bash
# Fast poller — no sleep, for metrics that don't need delta calculation

mem=$(free | awk '/^Mem:/{printf "%.0f", $3/$2 * 100}')
echo "mem=$mem"

temp=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null)
[ -n "$temp" ] && echo "temp=$((temp / 1000))" || echo "temp="

disk=$(df / | awk 'NR==2{gsub(/%/,"",$5); print $5}')
echo "disk=$disk"

vol_raw=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null)
vol=$(echo "$vol_raw" | awk '{printf "%.0f", $2 * 100}')
echo "vol=$vol"
echo "$vol_raw" | grep -q MUTED && echo "muted=true" || echo "muted=false"

wpctl get-volume @DEFAULT_AUDIO_SOURCE@ 2>/dev/null | grep -q MUTED && echo "micmuted=true" || echo "micmuted=false"

bat=$(cat /sys/class/power_supply/BAT*/capacity 2>/dev/null)
echo "bat=$bat"
batstatus=$(cat /sys/class/power_supply/BAT*/status 2>/dev/null)
echo "batstatus=$batstatus"
