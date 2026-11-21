# S07 disposable host-view test receipt

**Status:** Local test GREEN; independent review passed; production/live gates open.

Assigned scope: isolated nonsecret host-directory FIM preparation, no production
FIM enablement until deployed S06 verification and retention/recovery decisions.
This checkout is based on S06 `65354915`. The user has accepted retention and
backup/restore behavior; the approved destination is still being grounded.
No backup location or credentials are inferred.

RED: `/tmp/wazuh-s07-red.log` records the existing disabled fixture's missing
native FIM scan/event assertion (12-second deadline). The daemon ran, and the
fixture existed; no missing-file test is counted as RED.

First enabled attempt exposed a harness mismatch: native UNIX datagrams have a
trailing NUL. The parser now removes only that framing character. Inspecting
pinned `src/syscheckd/src/main.c` also showed rootcheck reads default configuration
independently of the FIM `-c` path. The fixture therefore mounts the complete
configuration at `/var/ossec/etc/ossec.conf` and asserts no rootcheck messages.
These are documented harness repairs, not evidence of deployed behavior.

GREEN command:

```bash
pytest -q tests/wazuh-agent-canary/fim_host_view.py \
  tests/wazuh-agent-canary/trust_handshake.py \
  tests/wazuh-agent-canary/test_contract.py
```

Result: 15 passed. The explicit CI trust step now also invokes the FIM fixture.
The image digest comes from the existing Orion module; tests use `--pull=never`
after the CI pull, no fallback/skip. The new test starts a fresh bounded container
with network disabled and captures its native UNIX event queue. One mutation
and one restoration are required, with exact restored hash, no content/diff,
no unmounted control, no rootcheck, bounded count and rejected container write.

Receipt limits: the fixture disables manager synchronization and cannot prove
manager attribution/indexing/delivery, production root ownership, hostile-host
path resistance, broad configuration coverage, seven-day performance or restore.
The baseline and collector tests remain unchanged. No host system evaluation is
needed for this tests-only slice; the predecessor's Orion dry-run passed.

Decision metadata: the native tool initially returned only `accepted: true`,
so no question ID was invented. The answered question later returned ID
`call_7676c6caadfb46708fde8d45ec0386f1`, item 0. Asked approximately
2026-11-21 19:10 UTC: “Wazuh has no documented index-retention or restore policy.
Which backup destination and retention should S07 use?” User answer, verbatim:
“do as recomendation”. Accepted behavior is 30-day alert retention, daily
encrypted index snapshots, manager-state backup and an isolated restore.
The coordinator is grounding an existing approved destination and owner;
no additional retention approval is required. Checkout:
`desktop-nixos/worktrees/wazuh-fim-s07`, base `65354915`, this test-contract
revision. Live activation remains blocked on deployed S06 verification and
backup/restore evidence. No review-session ID was supplied for the native
question; Homelab records the same decision.

Independent review found a narrow assertion gap: only the restored event was
checked structurally for absence of a diff. Both event SHA-256 values now must
match the exact changed/original sequence, and neither may contain a diff field.
All 15 tests passed again after this assertion-only repair.

Fresh reviewer reran the corrected FIM fixture (1 passed) after independently
running the combined suite (15 passed); no remaining material source findings.
