# Compiler-cache writer verification

**Status:** Test contract for the accepted source policy, 2026-10-29.

[Human seed and answer](behavior.md) govern this slice. The implementation belongs
to the cache server in `modules/services/sccache.nix`. A narrower ACL alone
cannot override Discovery's independent wildcard grant, so enforce mutation at
the HTTP server while preserving read reachability and existing client settings.

The isolated Nix leaf contract must first fail because mutations have no writer
boundary. It must then allow exactly the three accepted synthetic remote
identities and local loopback maintenance, preserve DAV methods and the
tailnet-specific firewall port, and deny other mutation sources:

```sh
python3 -m unittest discover -s tests/sccache-security -p 'test_*.py' -v
```

The native HTTP fixture renders that same module with synthetic host and peer
addresses. The legacy laptop address belongs to `fleet.tailnetPeers` in
`modules/meta.nix`, exported by `just fleet-json`; it is not a `fleet.hosts`
entry or a deployment target. The source contract renders the current exported
artifact and verifies that changing the named peer changes its writer address
without granting writes to other metadata peers. Before that repair, three
assertions failed: the peer map was absent and the service ignored both default
and replacement synthetic peer addresses. The build never reads a sibling
working tree. The fixture
runs Nginx on an ephemeral loopback port, and verifies successful writes/deletes,
unchanged GET/HEAD reads, denied PUT/DELETE/MKCOL/COPY/MOVE, and rejected forwarding
header spoofing. It uses no real cache, tailnet address or credential:

```sh
python3 tests/sccache-security/verify_http.py --nginx /absolute/path/to/nginx
```

The command exits zero and prints `SCCACHE_WRITER_BOUNDARY_OK` only after all
assertions pass. Missing tools or startup failures are setup failures, not RED.
The isolated renderer does not replace effective NixOS evaluation. Required
owner checks remain `just lint`, `just fmt-check`, `just docs-check`, and the
Orion toplevel dry build. Use the documented local `nix build --dry-run`
equivalent without remote builders in this source-only task.

Before later deployment, verify effective writer addresses and preserve a
recovery path. Runtime host firewall/tailnet enforcement and real Cargo cache
fallback remain separate observations. If cache authorization fails, compile
locally while correcting the identity mapping; do not restore unrestricted
remote writes as an automatic rollback.
