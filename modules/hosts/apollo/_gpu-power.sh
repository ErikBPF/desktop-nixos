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
    0X248810DE|0X248410DE) watts=170; clocks=210,1500 ;; # RTX 3070; retain proven fault limits.
    0X2D0410DE) watts=145; clocks= ;; # RTX 5060 Ti; provisional efficiency ceiling.
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
  if [[ -n "$clocks" ]]; then
    nvidia-smi --id="$uuid" --error-on-warning --lock-gpu-clocks="$clocks" || status=1
  fi
done <<< "$inventory"
exit "$status"
