# Orion Wazuh host SSH evidence

## Accepted scope and grounding

The user selected Wazuh after the September 12 proposal batch and requested
host placement first. The accepted fleet Wazuh proposal's I2 requires real
host authentication signals. Live mapping found one active `orion-canary`
agent, but its only host mount was `client.keys`; the existing probe appended
synthetic text inside the container. This slice fixes that coverage gap before
another host is enrolled. It does not create or overwrite a human seed.

## Runtime premise correction — September 13 UTC

The first deployed probe failed: the real SSH journal marker existed but no
manager alert arrived. Inside the pinned agent, `sd_journal_open_files` returned
`-93 / EPROTONOSUPPORT` for Orion's journal. Successful configuration parsing
and the agent's monitoring message did not prove format compatibility.

The implementation choice below supersedes direct journal mounts. Host-native
rsyslog `imjournal` reads the host format and exports only trusted SSH-unit
records to a protected, rotated text file. This adds one standard logging
service and removes whole-journal read access from the container. The accepted
behavior remains real host SSH coverage, with existing enrollment preserved.

## Contract

- Keep the existing Orion identity, pinned 4.14.7 image, enrollment state and
  runtime OpenBao/Sops credential delivery. No other host is enrolled.
- Host rsyslog uses its journal input and exact trusted `_SYSTEMD_UNIT` equal
  to `sshd.service`; socket-originated records and unrelated units are excluded.
  Disable its broad default file outputs, persist its cursor, and skip historical
  backlog on first start. Disable the input's default burst dropping so unrelated
  journal volume cannot consume the SSH collection budget.
- Export to `/var/log/wazuh-host/sshd.log`, directory 0700 and file 0600 root-owned.
  Rotate by rename/create and HUP reopen, not copytruncate. Seven daily rotations
  and a 10 MiB scheduled size threshold bound retained files; the threshold is
  not an instantaneous hard disk cap.
- Bind only that directory read-only into the agent so rotation remains visible.
  No host journals, machine ID, privileged mode, host PID namespace or engine socket.
- Use one `syslog` localfile collector for the filtered file. This includes
  `sshd-session` records without collecting unrelated unit events.
- Mount the nonsecret configuration at the image's supported configuration
  import path, so startup can copy and substitute it. Do not mount its writable
  `/var/ossec/etc/ossec.conf` directly.
- Disable container rootcheck, FIM, inventory and SCA; no command collectors.
  Do not report container observations as host security coverage.
- Replace the container-text probe with one bounded invalid-user SSH attempt
  against Orion's loopback sshd. Require the unique marker in the real host SSH
  journal, filtered file and a fresh, attributed manager alert. Missing evidence
  fails. A separate SSH-shaped record from one unrelated transient unit must be
  present in its own journal but absent from the filtered file after the positive
  record has flowed. Record this bounded exclusion check without raw log output.

The host reader can access journals; the container receives only the filtered
SSH file. Native cursor persistence may replay a bounded suffix after an abrupt
reader failure; exactly-once delivery is not claimed.

## RED / GREEN and acceptance

1. Extend the existing `tests/wazuh-agent-canary/test_contract.py` checks for
   filtered mounts, trusted-unit export, XML collector/disabled scanners, rotation
   and the host-origin/exclusion probe.
   Observe assertions fail against the transport-only implementation.
2. Implement the minimum module/configuration and recipe changes. Run those
   tests, evaluate Orion's actual mounts, validate the actual rsyslog configuration and XML with their pinned
   parsers, and run `just dry orion`, lint, format and documentation checks.
3. Review conformance and security independently. Publish/deploy only through
   the existing reviewed workflow. After deployment, run the bounded probe and
   confirm an unrelated unit is excluded. Seven-day observation and further
   enrollment remain open; local checks cannot close live acceptance.

Rollback: restore the prior module/configuration and recipes through the normal
deployment path. Preserve enrollment state and credentials; no key rotation,
manager migration or shared IAM expansion in this slice. The rsyslog reader
is the only additional service.
