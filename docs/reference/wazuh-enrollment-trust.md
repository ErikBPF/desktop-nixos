# Wazuh enrollment trust and FIM handoff

**Status:** S06 source prepared; live sequence held for coordinator. S07 is preparation only.

## Trust boundary and provenance

The public pin's authenticated provenance, fingerprint, validity and owners are
recorded in the [S06 receipt](../behaviors/wazuh-s06/one-pager.md). Never obtain a
replacement by trusting an unauthenticated network certificate. Verify through
the existing authenticated manager control path, review the public identity,
then publish a coordinated pin update. Do not run the broad bootstrap-secrets
recipe: it rotates unrelated credentials and does not own this persisted authd
certificate. Protect and restore the existing manager PVC; this change adds no
new certificate authority or standing credential.

Pinned Wazuh 4.14.7 source:

- [Enrollment verification](https://github.com/wazuh/wazuh/blob/a42268a27c555d9348d5598fb8751eaf4c8e9024/src/shared/enrollment_op.c)
  checks the certificate before constructing/sending the password-bearing request.
- [Name verification](https://github.com/wazuh/wazuh/blob/a42268a27c555d9348d5598fb8751eaf4c8e9024/src/os_auth/check_cert.c)
  accepts a matching SAN or falls back to CN. The current self-signed v1
  certificate has only CN; the registration alias matches it exactly.
- [Manager identity documentation](https://documentation.wazuh.com/current/user-manual/agent/agent-enrollment/security-options/manager-identity-verification.html)
  describes `server_ca_path`. Current documentation is secondary to the pinned
  source and actual 4.14.7 fixture results.

Port 1515 enrollment TLS and port 1514 encrypted event transport are separate.
This patch preserves the existing symmetric enrolled identity; it does not claim
new TLS verification on the event channel or retrospective proof that initial
enrollment was trusted.

## Local proof and proposed live sequence

Run the explicit `trust_handshake.py` pytest suite after pulling the image pinned
in the Orion module. CI uses Docker; local fixtures use rootless Podman. The
suite tests actual 4.14.7 enrollment code against trusted, untrusted, wrong-name
and missing-anchor cases, including a CN-only self-signed certificate. It never
contacts the production manager or mounts standing identity.

After source review, publication and coordinator approval of the activation diff:

1. Recheck the public manager fingerprint and PVC provenance through the existing
   authenticated Kubernetes context. Stop on any mismatch; do not auto-accept it.
2. A bounded TLS-only live probe can verify the actual server without sending an
   enrollment request or changing manager identity records:

   ```bash
   timeout 10 openssl s_client -tls1_2 -connect 192.168.10.250:1515 \
     -servername wazuh-manager-master-0 -verify_hostname wazuh-manager-master-0 \
     -CAfile modules/hosts/orion/wazuh-enrollment-ca.pem \
     -verify_return_error </dev/null
   ```

   Require successful certificate verification. This is a TLS trust probe, not
   proof of Wazuh enrollment or a replacement for the pinned-agent negative tests.
3. Use owner `just dry orion` and reviewed deployment recipes. Do not delete or
   replace `/var/lib/wazuh-agent/client.keys`, run `agent-auth` against the live
   manager, or recreate `orion-canary` to manufacture a trust receipt.
4. Capture the enrolled agent's ID/name before and after the controlled restart;
   compare identity bytes privately without printing keys. Run existing
   `just probe-wazuh-agent-canary` / `just verify-wazuh-agent-canary` for newly
   attributed host SSH evidence. Merely finding old alerts is insufficient.
5. Record results and recovery before enabling S07. Revert only source/config
   if startup fails; preserve manager PVC, enrollment identity and host SSH logs.

## S07 narrow host-view preparation

Do not enable FIM before S06's live gate. The first proposed Orion scope is only
`/var/lib/wazuh-fim-canary/watched/sshd_config.fixture`, root-owned harmless text,
with an unwatched control under `/var/lib/wazuh-fim-canary/control/`. Bind only
the watched directory read-only at `/host-fim` in the existing agent; watch that
explicit path with file-content diffs disabled. No broad host `/etc` mount,
private keys, shadow, credentials, home trees, rootcheck or inventory is selected.

The fixture must prove host mutation and restoration, not container `/etc`
changes. Test an unwatched control and check retained `orion-canary` attribution,
no content/diff payload, bounded event count and the exact manager notification.
A host NixOS `/etc` symlink or single-file bind can retain an old inode across
configuration replacement; do not generalize this directory fixture to real
NixOS configuration coverage. Real configuration paths need a separate proven
host-view choice, potentially native monitoring rather than a broader mount.

Before implementation/activation, settle index lifecycle retention and exercise
the existing manager/indexer restore path under explicit authority; PVC size is
not evidence. Record agent heartbeat loss/recovery without duplicate health
routing, resource baselines and seven days of observation. Acceptance limits:
steady RAM at most 5% of host RAM, sustained CPU at most 2%, no valueless
duplicates. Workstation expansion needs its own selected identity and trust
proof; no shared fleet module or new credential is introduced here.

### Retention and restore decision still required

Source inspection found no Wazuh-specific index retention policy or restore
recipe. Do not describe an existing proven restore path. Proposed minimum:
30 days of alert-index retention, daily encrypted index snapshots and manager
state backup, then an isolated restore whose event counts/IDs and manager
identity match the captured baseline. The coordinator must select the existing
sanctioned backup destination and recovery budget before implementation.
Applying retention to `wazuh-alerts-*` also affects existing SSH alerts, so that
policy requires an explicit decision; no deletion policy is installed here.

A concrete first FIM slice, after deployed S06 verification, would add only the
Orion directory bind and one syscheck rule: realtime on `/host-fim`, recursion
level 0, file limit 8, max 10 events/second and `report_changes="no"`. Create only
one watched fixture and one outside control; change once, restore once, verify
the two attributed events and no control/content events. Use an isolated
fixture first to verify those exact options against 4.14.7. Keep the existing
SSH collector and client key untouched. Remove the rule/bind through source
rollback if acceptance fails; do not delete enrollment or reset its baseline.
