# Manual test suites

These suites need a live host, root, network, or a Nix evaluation. No gate runs
them. Run the listed command from the repository root on a suitable host.

| Directory | Command | Prerequisite |
|---|---|---|
| `tests/alloy` | `pytest -q tests/alloy` | docker |
| `tests/alloy-containers` | `pytest -q tests/alloy-containers` | docker |
| `tests/apollo-host` | `pytest -q tests/apollo-host` | runtime state |
| `tests/apollo-worklab` | `pytest -q tests/apollo-worklab` | ssh host, network, root |
| `tests/argus-security` | `pytest -q tests/argus-security` | docker, network, root |
| `tests/cognee-recovery` | `pytest -q tests/cognee-recovery` | docker |
| `tests/dendritic-structure` | `pytest -q tests/dendritic-structure` | ssh host |
| `tests/desktop-file-managers` | `pytest -q tests/desktop-file-managers` | runtime state |
| `tests/fail2ban-sshd-session` | `pytest -q tests/fail2ban-sshd-session` | nix eval |
| `tests/fleet-dns-lan` | `pytest -q tests/fleet-dns-lan` | nix eval |
| `tests/harbor-host-auth` | `pytest -q tests/harbor-host-auth` | docker |
| `tests/harbor-iam-acceptance` | `pytest -q tests/harbor-iam-acceptance` | network |
| `tests/harbor-iam-preflight` | `pytest -q tests/harbor-iam-preflight` | ssh host, docker, network, root |
| `tests/harbor-version-reconcile` | `pytest -q tests/harbor-version-reconcile` | docker |
| `tests/herdr-worklab` | `pytest -q tests/herdr-worklab` | ssh host, nix eval, network |
| `tests/hermes-go-credentials` | `pytest -q tests/hermes-go-credentials` | network |
| `tests/kepler-collision-recovery` | `bats tests/kepler-collision-recovery` | ssh host, docker |
| `tests/opencode-work-provider` | `pytest -q tests/opencode-work-provider` | network |
| `tests/orion-audit` | `pytest -q tests/orion-audit` | nix eval |
| `tests/orion-main-guardrails` | `pytest -q tests/orion-main-guardrails` | nix eval, network |
| `tests/orion-upgrade-diagnostics` | `pytest -q tests/orion-upgrade-diagnostics` | ssh host |
| `tests/public-host-journal-telemetry` | `pytest -q tests/public-host-journal-telemetry` | nix eval |
| `tests/public-host-ssh` | `pytest -q tests/public-host-ssh` | nix eval |
| `tests/servarr` | `pytest -q tests/servarr` | runtime state |
| `tests/servarr-exact-revision` | `pytest -q tests/servarr-exact-revision` | root |
| `tests/shell-aliases` | `pytest -q tests/shell-aliases` | runtime state |
| `tests/tmux-persistence` | `pytest -q tests/tmux-persistence` | network |
| `tests/tuicr` | `pytest -q tests/tuicr` | runtime state |
| `tests/wazuh-agent-canary` | `pytest -q tests/wazuh-agent-canary` | docker |
