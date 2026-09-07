# OpenBao authenticated probe

**Status:** Implementation; offline behavior verified before rollout.

Owner: desktop-nixos. Extend the existing five-minute `openbao-seal-probe`
without another identity, policy, timer, or secret-value fetch. The effective agent
sink in `_vault-agent.nix` writes `/run/vault-agent/token` with mode 0640.
The IaC agent AppRole does not disable the default policy, whose lookup-self
permission supports this canary. HTTP 200 confirms the current agent token
can authenticate; it does not prove every consumer policy or render is valid.

Planning exchange: operator needs a credential failure signal despite an
unsealed server; security rejects root tokens and response logging (lookup-self
returns token metadata); implementer reuses the existing timer and atomic
textfile publication. Decision: loopback GET lookup-self with the existing
agent token passed through curl stdin headers. Never put it in argv, an
environment variable, a new file, or diagnostic output. Missing/empty/multiline
tokens and every non-200 response produce failure. No redirect following.

Contract: `probe.feature` is unautomated Gherkin. The runnable test extracts
the actual deployed shell and uses a synthetic loopback HTTP server. RED:
HTTP 200/403/500 and missing-token cases all failed because authentication
metrics were absent. GREEN: append success and attempt timestamp to the same
atomic metric publication; preserve `openbao_sealed` and timer cadence.

Metric contract (unlabelled gauges in `openbao_sealed.prom`):
- `openbao_authenticated_probe_success`: 1 only on authenticated HTTP 200;
  otherwise 0.
- `openbao_authenticated_probe_timestamp_seconds`: Unix seconds at completion
  of each attempt, including failures. Old files retain old timestamps when
  the process cannot publish, so freshness remains observable.

Grill: token renewal races may cause one failure, so alerting needs a grace
period. No response-body parsing, credential retention, or new policy grants.
GitOps owns alerting: failure, absence, or timestamp age over two probe
intervals (600 seconds), with five-minute grace. Publish this owner metric
first; deploy consumer alert rules afterwards. No probe-triggered webhook.

Checks: `python3 -m unittest discover -s tests/openbao-probe -p 'test_*.py'`,
repository lint/fmt, Discovery dry build, then live metric freshness and
service checks after parent-managed deployment. Revert the probe addition to
roll back; the old seal-status metric remains valid throughout.
