#!/usr/bin/env bash
# Publish per-container Docker health to the node-exporter textfile collector.
#
# cAdvisor on this Alloy version caches container health at discovery, so a
# container started after Alloy reports a stale value (observed: 118 series,
# only the four containers present at first scrape reported healthy). Read the
# live Docker state on every run instead, and let Grafana alert on sustained
# unhealth.
set -euo pipefail

metric_dir=${1:?metric directory required}
host=${2:?host label required}
output="${metric_dir}/container-health.prom"
tmp="${output}.tmp"

# Fail before truncating the metric file when the runtime is unreachable, so the
# last good sample survives instead of the alert firing on missing data.
names=$(docker ps --format '{{.Names}}')

{
  while IFS= read -r name; do
    [ -n "${name}" ] || continue
    project=$(docker inspect --format '{{index .Config.Labels "com.docker.compose.project"}}' "${name}" 2>/dev/null || true)
    [ -n "${project}" ] || project=none
    status=$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "${name}" 2>/dev/null || true)
    unhealthy=0
    [ "${status}" = unhealthy ] && unhealthy=1
    printf 'container_health_unhealthy{host="%s",name="%s",project="%s"} %s\n' \
      "${host}" "${name}" "${project}" "${unhealthy}"
  done <<< "${names}"
} > "${tmp}"

mv "${tmp}" "${output}"
