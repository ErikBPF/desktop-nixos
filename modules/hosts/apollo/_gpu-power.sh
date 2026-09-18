#!/usr/bin/env bash
set -euo pipefail

inventory=$(nvidia-smi --query-gpu=uuid,pci.device_id --format=csv,noheader,nounits)
if [[ -z "$inventory" ]]; then
  echo "No NVIDIA GPUs found; power policy not applied" >&2
  exit 1
fi

status=0
while IFS=', ' read -r uuid device extra; do
  if [[ "$uuid" != GPU-* || -n "$extra" ]]; then
    echo "Malformed NVIDIA inventory; refusing this device" >&2
    status=1
    continue
  fi
  case "${device^^}" in
    0X2D0410DE) watts=150 ;; # RTX 5060 Ti; lowest firmware-permitted ceiling (min 150 W).
    *)
      echo "No reviewed power policy for $uuid ($device)" >&2
      status=1
      continue
      ;;
  esac
  if ! nvidia-smi --id="$uuid" --error-on-warning --power-limit="$watts"; then
    status=1
    continue
  fi
  nvidia-smi --id="$uuid" --error-on-warning --reset-gpu-clocks || status=1
done <<< "$inventory"
exit "$status"
