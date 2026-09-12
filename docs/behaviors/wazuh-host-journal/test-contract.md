# Orion Wazuh host SSH evidence

## Accepted scope and grounding

The user selected Wazuh after the September 12 proposal batch and requested
host placement first. The accepted fleet Wazuh proposal's I2 requires real
host authentication signals. Live mapping found one active `orion-canary`
agent, but its only host mount was `client.keys`; the existing probe appended
synthetic text inside the container. This slice fixes that coverage gap before
another host is enrolled. It does not create or overwrite a human seed.

## Contract

- Keep the existing Orion identity, pinned 4.14.7 image, enrollment state and
  runtime OpenBao/Sops credential delivery. No other host is enrolled.
- Read host persistent and runtime journals and machine identity through
  read-only mounts. No privileged mode, host PID namespace, engine socket,
  or writable host journal mount.
- Use the pinned image's native journald reader, with exactly one localfile
  collector filtered by `_SYSTEMD_UNIT` equal to `sshd.service`. This includes
  `sshd-session` records without collecting unrelated unit events.
- Mount the nonsecret configuration at the image's supported configuration
  import path, so startup can copy and substitute it. Do not mount its writable
  `/var/ossec/etc/ossec.conf` directly.
- Disable container rootcheck, FIM, inventory and SCA; no command collectors.
  Do not report container observations as host security coverage.
- Replace the container-text probe with one bounded invalid-user SSH attempt
  against Orion's loopback sshd. Require the unique marker in the real host SSH
  journal and a fresh, attributed manager alert. Missing evidence fails.

Read-only journal mounts expose the host journal to the agent process;
collection filtering limits transmitted events, not the process's read access.
This is an explicit trust boundary for this rootful host-security canary.

## RED / GREEN and acceptance

1. Extend the existing `tests/wazuh-agent-canary/test_contract.py` checks for
   host mounts, XML filter/disabled collectors, and the host-origin probe.
   Observe assertions fail against the transport-only implementation.
2. Implement the minimum module/configuration and recipe changes. Run those
   tests, evaluate Orion's actual mounts, validate XML with the pinned agent's
   parser, and run `just dry orion`, lint, format and documentation checks.
3. Review conformance and security independently. Publish/deploy only through
   the existing reviewed workflow. After deployment, run the bounded probe and
   confirm an unrelated unit is excluded. Seven-day observation and further
   enrollment remain open; local checks cannot close live acceptance.

Rollback: restore the prior module/configuration and recipes through the normal
deployment path. Preserve enrollment state and credentials; no key rotation,
manager migration, shared IAM expansion, or new logging daemon in this slice.
