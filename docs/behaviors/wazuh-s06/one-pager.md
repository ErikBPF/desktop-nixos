# S06: verify Orion's enrollment manager

**Status:** Source and disposable handshake gates passed; independent review and TLS-only live probe passed; deployment pending. S07 remains gated.

## Outcome and why

An enrolled agent sending SSH events did not prove that future enrollment would
reject an impostor manager. Orion now pins the existing manager's public
certificate and checks its identity before sending enrollment credentials.
No certificate is issued, rotated or copied with a private key; no agent is
re-enrolled. Port 1514 retains its existing address and persisted symmetric
`client.keys` identity. The TLS change concerns enrollment on port 1515.

The work uses Desktop base `68ca18d8` and GitOps base `05ff0c7`, each in its own
`worktrees/wazuh-trust-s06` checkout. Existing unrelated working trees remain
untouched. Agent and manager remain pinned to Wazuh 4.14.7.

## Changes and trust ownership

The agent XML adds `server_ca_path`; Nix mounts a public-only PEM read-only and
maps registration-only hostname `wazuh-manager-master-0` to `192.168.10.250`.
That alias matches the certificate's CN. The event endpoint, `orion-canary`
identity, Vault enrollment-password reference, persistent keys, host SSH feed
and dependency recovery remain unchanged. FIM, rootcheck and inventory remain
disabled. Public certificate indexing is explicitly excluded in `.graphifyignore`.

Authenticated `kubectl --context homelab` inspection on 2026-11-21 read only
`openssl x509` public output from `/var/ossec/etc/sslmanager.cert`. The subject
and issuer are `CN=wazuh-manager-master-0`; the certificate has no SAN or other
extensions, valid 2026-09-21 through 2036-09-18. SHA-256 fingerprint:
`3D:53:33:FB:58:6F:22:DA:2A:72:71:23:9F:F4:3A:EB:B0:F9:20:3F:35:2D:0A:66:76:94:00:B4:34:9B:05:27`.
The manager's `/var/ossec/etc` is a persistent PVC subpath in both source and
observed pod metadata. GitOps adds regression guards for master routing, that
mount, and the password-enabled authd certificate paths; no manager manifest
change is necessary.

GitOps owns manager certificate lifecycle and PVC recovery; Desktop owns its
public trust pin. Any replacement, expiry, manager identity change or PVC loss
requires a coordinated authenticated certificate review and staged pin update.
Do not remove verification to recover enrollment. This certificate is not the
indexer/dashboard CA. Its private key was never read or exported.

## Evidence and limits

The pinned upstream source (`a42268a27c555d9348d5598fb8751eaf4c8e9024`)
verifies the chain and SAN/CN before writing the enrollment request. Real pinned
`agent-auth` fixtures reproduced four RED assertions: absent CA configuration,
untrusted/wrong-name acceptance and failure to fail closed without an anchor.
After the change, 14 tests passed, including trusted acceptance, rejection before
password transmission, missing-anchor rejection and a self-signed CN-only v1
certificate matching the existing manager's certificate shape. Two disposable
container initializations preserved the synthetic identity bytes and SSH input;
actual `wazuh-agentd -t` parsed the rendered XML.

Desktop lint, format and Orion offline toplevel dry-run passed. GitOps's Wazuh
contract passed with an existing Python environment containing PyYAML. Its first
attempt lacked PyYAML: a harness failure, not RED. CI now explicitly runs the
static canary contracts and disposable handshake suite. Full runtime SSH recovery,
standing identity preservation and notification delivery are still unobserved.

## Continuing work and recovery

Fresh independent review reproduced all 14 tests and found no material source
blocker. An authorized TLS-only probe of the current manager also passed with
the pinned certificate and exact CN under TLS 1.2, without sending an enrollment
request or password. This does not close deployed Orion recovery acceptance.

Follow the [runbook](../../reference/wazuh-enrollment-trust.md) after independent
review and coordinator sequencing. Compare the Orion candidate/current closure
before activation. Preserve enrolled keys and SSH collection throughout; revert
only this source change if necessary without modifying manager state. S07's
narrow host-view proposal, live mutation proof, retention/restore evidence and
observation gates remain separate; no fleet expansion is implied.
