# OpenBao ingress and audit hardening

**Status:** Implemented; deploy and verification commands below are the rollout gate.

Discovery runs OpenBao on loopback, its tailnet address, and the dedicated
SWAG bridge. SWAG terminates TLS and permits only LAN/tailnet source addresses.
No Docker gateway or forwarded request header is an authentication boundary.

Tailscale marks forwarded packets and SNATs them in POSTROUTING. Docker DNAT
turns Discovery-published HTTPS into forwarded traffic, so SWAG previously saw
`172.18.0.1` and returned 403 even for allowed tailnet clients. The host firewall
now clears only Tailscale's SNAT bit for marked tailnet-source TCP/443 packets
DNATed from Discovery's LAN/tailnet addresses toward a Docker bridge. Other
ports, direct container traffic, and subnet-router traffic retain normal SNAT.
Tailscale ACL processing happens before this rule. The kernel regression test
must pass after Tailscale/netfilter upgrades because the mark is an integration
detail. No nginx allowlist was expanded.

One declarative file audit device writes HMAC-protected records to
`/var/log/openbao/audit.json`, mode 0600, under a private service log directory.
API-created audit devices are disabled. Logrotate checks daily, rotates above
25 MiB or daily, retains 14 rotations, compresses after a delay, and sends HUP
to reopen the file. This is a rotation threshold, not a hard disk-usage cap.
Audit logs contain sensitive metadata even when values are HMAC-protected;
do not print them or ship them through general-purpose log collectors.

Validation:

```sh
sudo unshare --net python3 tests/openbao-ingress/test_network.py
nix eval --json .#nixosConfigurations.discovery.config.services.openbao.settings > /tmp/openbao-settings.json
# Pass the pinned package's bin/bao to tests/openbao-hardening/test_audit.py.
just lint
just fmt-check
just dry discovery
```

Deployment uses the normal `just switch-discovery` entry point. OpenBao does
not auto-restart on activation: its immutable config path requires one controlled
restart. Then run `just restart-openbao-with-backup`, which takes a fresh local
Raft backup before restart and invokes the existing unseal service. Finish with
`just verify-openbao-hardening`. It proves external health, authentication still
required for secrets, rejection of spoofed forwarding headers, private audit
file permissions, and active audit-device metadata without exposing values.

If activation fails, deploy-rs preserves its normal rollback safeguards. If the
OpenBao restart fails, preserve its state and use the
[existing recovery runbook](vault-disaster-recovery.md); never initialize a new
store or restore over production as an ingress fix.

References: [Tailscale subnet SNAT](https://tailscale.com/docs/reference/troubleshooting/network-configuration/disable-subnet-route-masquerading),
[OpenBao declarative audit](https://openbao.org/docs/configuration/audit/),
[file audit rotation](https://openbao.org/docs/audit/file/).
