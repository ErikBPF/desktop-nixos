#!/usr/bin/env bash
set -euo pipefail

target="${UBUNTU_WORK_SSH_TARGET:-erik@192.168.122.74}"
ssh -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=yes "$target" \
  'sudo env DEBIAN_FRONTEND=noninteractive apt-get remove -y ampagent'
