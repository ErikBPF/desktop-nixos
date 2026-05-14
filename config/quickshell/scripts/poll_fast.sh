#!/usr/bin/env bash
# Slow poller — mem, disk, temp, governor, platform profile (no event source)
# Audio and battery moved to Pipewire/UPower QML services.

mem=$(free | awk '/^Mem:/{printf "%.0f", $3/$2 * 100}')
echo "mem=$mem"

temp=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null)
[ -n "$temp" ] && echo "temp=$((temp / 1000))" || echo "temp="

disk=$(stat -f -c '%a %b' / | awk '{printf "%.0f", (1 - $1/$2) * 100}')
echo "disk=$disk"

governor=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null)
echo "governor=$governor"
platform=$(cat /sys/firmware/acpi/platform_profile 2>/dev/null)
echo "platform=$platform"
