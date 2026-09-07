# OpenBao audit rotation

**Status:** Implemented locally; deployment and live verification pending.

Human seed: restore failed ESO authentication caused by audit rotation and harden
OpenBao. Keep all existing credentials, policies, HMAC protection and mode 0600.

Root cause: host logrotate created `audit.json` with the dynamic numeric service
UID. In the service's idmapped LogsDirectory mount, that inode maps to nobody;
OpenBao cannot append, so audited requests fail closed with HTTP 500.

Decision: retain rename, delayed compression and SIGHUP. Emit `nocreate` and let
OpenBao create its own inode at the configured 0600 mode. No copytruncate,
audit-disable fallback, static identity, or recurring ownership repair.

References: [OpenBao file audit rotation](https://openbao.org/docs/audit/file/)
requires SIGHUP. [systemd directory ownership](https://www.freedesktop.org/software/systemd/man/latest/systemd.exec.html)
explains DynamicUser idmapped directory ownership. These explain the observed
host/service namespace mismatch; the production file metadata confirmed it.

[Feature](rotation.feature) is an unautomated behavior contract. Equivalent
regressions run through the existing real OpenBao dev-server test, with evaluated
logrotate settings supplied as its third argument. No new runner or dependency.

Implementation plan and review: one vertical slice changes `create` to false,
extends the existing isolated audit test, and adds a one-time fixed-file recovery
recipe. RED reproduced HTTP 500 for an unreadable precreated replacement and
rejected current evaluated `create`; GREEN restores synthetic access by letting
the server create its replacement and checks private HMAC output. Permission-denial
fixture is equivalent, not a full systemd idmapped-mount integration test.

Recovery: `just repair-openbao-empty-audit-owner` accepts only an active DynamicUser
service and an empty, regular, nonsymlink mode-0600 file whose owner differs from
the runtime UID/GID. Inspect ownership in the service mount namespace; follow
the systemd-managed directory symlink, never a file symlink. Change only the
file's ownership, then HUP and require a denied request to be audited. It never
removes or truncates audit data. Parent operator verifies authenticated AppRole
access and ESO reconciliation afterward. Nonempty files need a separate review.

Rollout: `just dry discovery`, reviewed deployment via existing `just` entry
points, then `just verify-openbao-hardening` and consumer probes. Do not roll back
to host-side creation; stop rotation for investigation if service-created files
cannot reopen. No secret values or raw audit records are retained in evidence.
