#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

grep -q '^profile := "endeavour"$' justfile
jq -e '.hosts.endeavour.tailscaleIp == "100.107.225.13"' fleet.json >/dev/null
jq -e '.hosts | has("laptop") | not' fleet.json >/dev/null
grep -q 'row endeavour ' justfile
if grep -Fq 'nixosConfigurations.laptop.config.system.build.toplevel' justfile; then
    exit 1
fi

# Render the selected commands without executing recipes or backtick expressions.
# Check both the default and an override so hard-coded targets cannot pass.
check_target() {
    local expected="$1" build dry
    shift
    build=$(just --no-dotenv --dry-run build "$@" 2>&1)
    dry=$(just --no-dotenv --dry-run dry "$@" 2>&1)
    grep -Fq -- ".#nixosConfigurations.$expected.config.system.build.toplevel " <<<"$build"
    grep -Fq -- "dry-build --flake .#$expected " <<<"$dry"
}

check_target endeavour
check_target endeavour endeavour
check_target apollo apollo
