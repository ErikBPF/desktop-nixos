# Durable cp1 boot containment before member replacement

**Status:** Source preparation only. No host activation or membership mutation.
Latest human seed: `continue`, following `do fixes`. Earlier approval was
“Approve the prepared cp-1 recovery, then merge KEDA and Wazuh (recommended)”
(question `call_0ed4ebcd1ba4494abee381d3ad1b7725`, item0). That authorized the
failed single snapshot-move attempt, not this new host or member-removal method. The accepted boundary remains:
no cp1 start against missing/quarantined etcd state before the reviewed replacement.

## Outcome and why

The guest recovery candidate disables automatic K3s startup, but the earlier
procedure retained the old host runner until after recovery. A host reboot
would run the old declarative installer, restore that old runner and boot a
cluster-initializing guest. Pinned MicroVM source `d70265960646e506757f8364e8585c17a06050e7`
rewrites `current` before boot; changing only that link cannot contain it.

This change adds `nixosConfigurations.kepler-cp1-recovery`. Normal fleet definitions are not replaced. The existing configuration mapper
also adds the supplemental host to the flake check set; full/check-remote
validation will include it. The focused evaluation gate is manual
(`nix eval --impure --raw --file tests/kepler-cp1-host-containment/evaluate.nix`,
see `tests/MANUAL.md`); it no longer runs on every pull request.
The supplemental host uses the native `microvm.vms.cp-1.evaluatedConfig` option
so the normal installer durably selects the reviewed no-autostart guest. It
uses the existing owner `deploy` recipe; the new `deploy-preview` recipe uses
the same flags with `dry-activate`.
All five sibling runners and their service definitions must remain
unchanged; cp1 retains its kernel, initrd, interfaces, volumes and shares.

## Exact source and credential custody

Published historical artifact `030d17cf4f9d56a40a3205d4af2ae7867a208e7d`
reproduces running host `zi7mrrickfv7haaglmy7yrsljr9zgk9p` exactly. It preserves deployed Syncthing without editing the separate compute worktree.

Artifact `a3f290e015eacce61e718f8596cdb6acc3716c7c` layers the exact encrypted
reader repair already approved in PR501. The baseline encrypted file SHA256 is
`0db92a31f95c9232920b032429a34589c01573dd3196d99902552b00882d0aa5`;
the reconciled file is
`4677ac8136bb743b1d01603d7d50446efdbf3347e915af8dd90972dfeb51f96d`.
No credential was rotated or decrypted. The historical artifact branch is never
a main-merge candidate. The current-main supplemental output pins this artifact
and the reviewed guest source `228bc67bf427fa1c4d33508f3f5967e2b1008d7a`.

## Evidence and limits

The source assertion first failed because the supplemental host selected old
runner `324az74…`, then passed after native evaluatedConfig selected `s226dm…`.
Receipts: `/tmp/kepler-host-containment-red.log` and
`/tmp/kepler-host-containment-green.log`. Final unit comparison shows the credential
layer changes the Home Manager unit store path (no activation-snippet changes;
only user Sops unit sources differ); the guest layer changes only
`install-microvm-cp-1.service` and `microvm@cp-1.service`. Source artifact
`a3f290e0` differs from exact baseline only in the approved encrypted file.

The disposable systemd ordering test exercises installer selection and translated
boot target edges, including failure before guest startup. It is not a real VM
reboot or a proof of etcd data recovery.

## Activation and failure boundary

**Proposed sequence, held for explicit live approval:** use the existing owner
preview/deploy recipes with target
`kepler-cp1-recovery 192.168.10.230`. Host deployment and explicit reachability
checks must finish before member removal. This route has no deploy-rs automatic
rollback. Dry activation may update directory metadata. Then verify running and
persistent host identities, effective installer, selected safe runner, and
unchanged guest boot ID/PID/booted runner. Keep the old guest reconcilers stopped.
The supplemental host disables boot counting temporarily: automatic fallback
to an old unsafe generation is forbidden; a failed boot may require console access. Verify its actual counter-free boot entry and exact default, with no
unsafe EFI one-shot/default override. Only a separately approved procedure may
remove the member and quarantine state.
After that point, never roll back to an old host generation that reinstalls the
unsafe runner. Old generations and archives are evidence, not automatic recovery
options. Later reviewed cleanup must restore normal guest restart, boot and reconciliation.

Two output-packaging failures preceded the successful build; neither was behavioral RED.

Boot-policy unit comparison, `just test-cp1-durable-boot`, and Nix evaluation passed. Built host:
`/nix/store/492mc5ylp5zjk6qmflyxw0jgayjwk4zz-nixos-system-kepler-26.11.20261115.5c3cda7`.
The bounded third build passed: `/tmp/kepler-host-containment-build-attempt3.log`.
The built deploy-rs wrapper `aq1z3l8…` deletes the bootloader default after switching,
so it is withdrawn from live use. The supplemental deploy node was removed; an
assertion failed before removal and passed afterward. Normal deploy-rs nodes remain
unchanged. Owner recipe expansion confirms preview and deployment differ only in
the action. The realized installer pins the safe guest and runner.

The held [owner sequence](../../reference/cp1-durable-recovery.md) requires the
[boot containment checks](../../reference/cp1-boot-containment-check.md) before member removal.
CI on initial head `caa12d00` misclassified the public encrypted-file SHA256 as an
API key; naming that expected hash separately preserves the assertion and passes
Gitleaks 8.24.3 without an allowlist.

Hosted P2 review identified source-retention risk. Both exact sources are now
declared flake inputs with NAR hashes; their own dependency locks remain intact.
Recursive comparison confirms all 85 prior input nodes unchanged despite lock-node
renaming. Retain `recovery/kepler-zi7-baseline` and `recovery/kepler-cp1-guest`
while any recovery consumer exists; never merge those historical artifact branches.
An offline evaluation still requires the referenced sources in the local store.
The final offline acceptance gate passed with the same built `492mc5…` host;
receipts are `/tmp/kepler-retention-eval.log` and
`/tmp/kepler-retention-lock-comparison.json`. Independent graph review passed.
