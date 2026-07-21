#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

grep -q '^profile := "endeavour"$' justfile
jq -e '.hosts.endeavour.tailscaleIp == "100.107.225.13"' fleet.json >/dev/null
jq -e '.hosts | has("laptop") | not' fleet.json >/dev/null
grep -q 'row endeavour ' justfile
grep -q 'nixosConfigurations.endeavour.config.system.build.toplevel' justfile
grep -q 'dry-build --flake .#endeavour' justfile
! grep -q 'nixosConfigurations.laptop.config.system.build.toplevel' justfile
