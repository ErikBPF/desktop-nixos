# S06 trust test contract and execution receipt

**Status:** Local source and disposable tests passed; live acceptance open.

The assigned behavior is S06 manager trust before S07 FIM, preserving Orion's
identity, SSH feed and restart recovery. Source scope: Orion Nix/XML/public pin,
canary tests, approved CI wiring, GitOps Wazuh persistence guards and owner docs.

`/tmp/wazuh-s06-red.log` records four observed assertion failures against the
baseline's absent `server_ca_path`: actual pinned `agent-auth` accepted both an
untrusted chain and wrong name, missing-anchor test also accepted because no
verification was selected, and the XML trust assertion failed. Seven existing/
positive checks passed. The handshake harness selects the CLI CA option from
XML presence; the CLI and daemon share upstream enrollment verification code.
The image-init test separately executes the shipped initialization script and
actual daemon configuration parser. It is not a claim that a production agent
was restarted or enrolled.

Final command set:

```bash
pytest -q tests/wazuh-agent-canary/test_contract.py tests/wazuh-agent-canary/trust_handshake.py
just lint
just fmt-check
nix build .#nixosConfigurations.orion.config.system.build.toplevel --dry-run --offline
# GitOps owning checkout, Python with PyYAML on PATH:
bash tests/wazuh-contract.sh
```

Results: 14 tests passed; lint, format, Orion dry-run and GitOps Wazuh contract
passed. Local dry-run receipt: `/tmp/wazuh-s06-orion-dry.log`. The first GitOps
attempt failed importing PyYAML; using an existing tool environment repaired the
harness without changing acceptance. Initial handshake fixture handling needed
to accept TLS rejection's BrokenPipeError and bounded listener cleanup; those
were harness repairs before the baseline RED, not implementation failures.

The image is pulled by immutable digest, then tests run with `--pull=never`.
Loopback TLS listeners, temporary synthetic certificates/password/identity and
fresh disposable container filesystems isolate all enrollment effects. Host
network mode connects only to the fixture's bound 127.0.0.1 endpoint. Host Wazuh
state and production passwords are never mounted. Container recreation tests
use `--network=none`. No skip or fallback counts as success.

Independent review passed: a fresh reviewer reproduced all 14 tests, checked
the pinned certificate/alias and manager persistence guards, and found no
material source defect. Repository hygiene (5 tests), structure and docs checks
also passed.

Authorized live TLS-only verification of `192.168.10.250:1515` used the pinned
public certificate and `-verify_hostname wazuh-manager-master-0`: exit 0,
`Verify return code: 0 (ok)`. The TLS 1.2 probe negotiated
`ECDHE-RSA-AES256-GCM-SHA384`, matching the pinned agent default protocol. Local
receipt: `/tmp/wazuh-s06-live-tls12.log`. No enrollment request, production
password or identity mutation occurred.

Real SSH recovery,
standing identity preservation and S07 notification/capacity/restore remain open.
