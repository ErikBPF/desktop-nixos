#!/usr/bin/env bash
# CPU poller — 500ms delta, runs every 2s

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

read -r u1 n1 s1 i1 w1 q1 sq1 st1 _ <<< "${cpu_before[cpu]}"
read -r u2 n2 s2 i2 w2 q2 sq2 st2 _ <<< "${cpu_after[cpu]}"
idle_d=$(( (i2+w2) - (i1+w1) ))
total_d=$(( (u2+n2+s2+i2+w2+q2+sq2+st2) - (u1+n1+s1+i1+w1+q1+sq1+st1) ))
[ "$total_d" -gt 0 ] && cpu=$(( 100 * (total_d - idle_d) / total_d )) || cpu=0
echo "cpu=$cpu"

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
