# Test contract — Argus bounded autonomy

| Scenario | Binding |
|---|---|
| Runner rejects unknown action, unknown target, and empty request without executing | `python3 modules/services/ops-fix/selftest.py` |
| Rate limit blocks a second restart inside the window | same |
| Restart is executed once and audited, then rate-limited | same |
| Tool rejects unsupported action and empty/oversized target locally | `python3 modules/hosts/discovery/hermes-plugins/ops-fix/selftest.py` |
| Tool reports an unavailable runner instead of raising | same |
| Tool off-mode refuses action | same |
| Registration exposes exactly `ops_fix` in toolset `ops_fix` | same |
| Discord toolset is exactly `{"ops_fix"}`; webhook stays empty | `python3 -m unittest tests/argus-security/test_argus.py` |
| Socket and plugin are mounted read-only; runner is imported and allowlisted | same |
| No `shell=True` or `subprocess` in the plugin | same |

Markers: `PASS ops-fix-selftest`, `PASS ops-fix-tool-selftest`, unittest OK.
No scenario is claimed from a deployed restart until one is observed.
