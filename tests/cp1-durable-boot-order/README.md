# Durable cp-1 boot selection: disposable ordering receipt

The old host installer can overwrite an operator-staged recovery runner when
the host boots. After the old member's database is quarantined, that would
select the old `clusterInit` guest. The containment proposal instead changes
the host's native `microvm.vms.cp-1.evaluatedConfig`, so its installer selects
the reviewed guest with no K3s boot target dependency.

This fixture evaluates the exact active `zi7` host source and published guest
`228bc67bf427fa1c4d33508f3f5967e2b1008d7a`. It extracts installer ordering,
the declared runner, installer `RemainAfterExit`, and guest K3s boot edges. Unique temporary user-systemd
units reproduce those edges; no system services or production resources are
changed. The installer executes the extracted link operation against temporary
paths. The hypervisor and K3s executable are deliberately replaced with stubs.

Observed RED: using the old evaluated installer fails with
`old installer restored unsafe boot runner`, despite initially staging the
candidate link. Observed GREEN: the candidate installer alone leaves the guest
inactive and preserves the old booted marker; two subsequent fresh systemd
transactions select the candidate and never invoke the K3s stub. All disposable
units are stopped and unlinked in `finally`.

Run the GREEN owner gate with `just test-cp1-durable-boot`. To replay the
historical RED and GREEN explicitly, use these exact published sources:

```sh
nix eval --offline --impure --json --expr 'import ./tests/cp1-durable-boot-order/fixture.nix { baselineUrl = "github:ErikBPF/desktop-nixos/030d17cf4f9d56a40a3205d4af2ae7867a208e7d"; recoveryUrl = "github:ErikBPF/desktop-nixos/228bc67bf427fa1c4d33508f3f5967e2b1008d7a"; }' > /tmp/cp1-durable-boot-fixture.json
python3 tests/cp1-durable-boot-order/systemd-smoke.py /tmp/cp1-durable-boot-fixture.json --old-installer
python3 tests/cp1-durable-boot-order/systemd-smoke.py /tmp/cp1-durable-boot-fixture.json
```

The first Python command must fail; the second must print
`CP1_DURABLE_BOOT_ORDER_SYSTEMD_OK`. Local receipts are
`/tmp/cp1-durable-boot-{red,green}.log`.

This proves translated systemd ordering and boot dependency behavior, not a
hypervisor reboot, NixOS activation, real missing-backend K3s execution, or
production safety. The active old guest's reconciliation units still need
containment. Exact host preservation, source activation preview, independent
review and explicitly authorized live sequencing remain separate gates. No
production membership or data was modified by these tests.

The old `booted` symlink is a simulated provenance marker, not a reproduction of
the host's `microvm-set-booted` service. No database is supplied or read: the
absence of a K3s start marker proves only that its evaluated boot edge is absent,
not what the real engine would do with missing etcd files.
