#!/usr/bin/env bash
# Returns all system info as key=value lines, one call for all metrics

# CPU — delta between two reads of /proc/stat (500ms apart for accuracy)
# Read all cpu lines (total + per-core)
declare -A cpu_before
while IFS=' ' read -r label rest; do
    [[ "$label" == cpu* ]] || break
    cpu_before["$label"]="$rest"
done < /proc/stat

sleep 0.5

declare -A cpu_after
while IFS=' ' read -r label rest; do
    [[ "$label" == cpu* ]] || break
    cpu_after["$label"]="$rest"
done < /proc/stat

# Calculate total CPU
read -r u1 n1 s1 i1 w1 q1 sq1 st1 _ <<< "${cpu_before[cpu]}"
read -r u2 n2 s2 i2 w2 q2 sq2 st2 _ <<< "${cpu_after[cpu]}"
idle_d=$(( (i2+w2) - (i1+w1) ))
total_d=$(( (u2+n2+s2+i2+w2+q2+sq2+st2) - (u1+n1+s1+i1+w1+q1+sq1+st1) ))
[ "$total_d" -gt 0 ] && cpu=$(( 100 * (total_d - idle_d) / total_d )) || cpu=0
echo "cpu=$cpu"

# Per-core for tooltip
cores=""
for key in $(printf '%s\n' "${!cpu_before[@]}" | grep 'cpu[0-9]' | sort -V); do
    read -r u1 n1 s1 i1 w1 q1 sq1 st1 _ <<< "${cpu_before[$key]}"
    read -r u2 n2 s2 i2 w2 q2 sq2 st2 _ <<< "${cpu_after[$key]}"
    id=$(( (i2+w2) - (i1+w1) ))
    td=$(( (u2+n2+s2+i2+w2+q2+sq2+st2) - (u1+n1+s1+i1+w1+q1+sq1+st1) ))
    [ "$td" -gt 0 ] && pct=$(( 100 * (td - id) / td )) || pct=0
    core_num="${key#cpu}"
    cores="${cores}C${core_num}:${pct}% "
done
echo "cpucores=${cores% }"

# Memory
mem=$(free | awk '/^Mem:/{printf "%.0f", $3/$2 * 100}')
echo "mem=$mem"

# Temperature
temp=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null)
if [ -n "$temp" ]; then
    echo "temp=$((temp / 1000))"
else
    echo "temp="
fi

# Disk
disk=$(df / | awk 'NR==2{gsub(/%/,"",$5); print $5}')
echo "disk=$disk"

# Volume
vol=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null | awk '{printf "%.0f", $2 * 100}')
echo "vol=$vol"
wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null | grep -q MUTED && echo "muted=true" || echo "muted=false"

# Mic
wpctl get-volume @DEFAULT_AUDIO_SOURCE@ 2>/dev/null | grep -q MUTED && echo "micmuted=true" || echo "micmuted=false"

# Battery
bat=$(cat /sys/class/power_supply/BAT*/capacity 2>/dev/null)
echo "bat=$bat"
batstatus=$(cat /sys/class/power_supply/BAT*/status 2>/dev/null)
echo "batstatus=$batstatus"

# WiFi
wifistatus=$(nmcli -t -f WIFI general 2>/dev/null | head -1)
echo "wifistatus=$wifistatus"

# Bluetooth
bluetoothctl show 2>/dev/null | grep -q "Powered: yes" && echo "bt=on" || echo "bt=off"
btdev=$(bluetoothctl devices Connected 2>/dev/null | head -1 | cut -d' ' -f3-)
echo "btdev=$btdev"
