# Orion voice host wiring

**Stage / revision:** RV / 2
**Status:** Validated source; not deployed.
**Owner / date:** desktop-nixos / 2026-11-21

The user requested voice inference through LiteLLM first, with workstation models as fallback, and authorized Orion model placement. This host slice adds the independent `voice` managed Compose stack and a Discovery-source TCP9000 firewall rule. The source address comes from fleet metadata. Servarr owns the workload and its published revision; the new stack must not replace or restart Orion's existing chat workload.

The host rule is not a standalone isolation guarantee: Tailscale packet-filter ordering can accept traffic earlier. The corresponding IaC ACL accept/deny assertions and live allowed/denied peer checks are required before backend activation. The Compose listener binds only Orion's Tailscale IPv4 address. Host-local and trusted shared-container processes remain inside the backend trust boundary.

Independent review identified and corrected fleet-address duplication and the missing Servarr `voice.yml` entry-point symlink. `just lint`, `just fmt-check`, and the final Orion system dry-build passed. No switch or managed stack activation occurred; runtime reachability and denial remain untested.

Orion runs NixOS 26.11.20261115.5c3cda7 with kernel 7.3.4. Its Servarr checkout pins `2090849b39b1b1112c0d98580d202ebe6459a10a`. The Servarr voice task branch was based on that exact pin, avoiding the unrelated mainline backlog. Publication and exact-pin delivery must precede this host activation. The shared chat inference endpoint timed out during synthetic checks; no shared runtime was restarted.

The coordinating desktop one-pager lives in the voice-dictation task checkout. OpenBao's documented root-bootstrap operation also awaits an authorized ephemeral token; normal AppRole credentials cannot modify their own policy. Continue backend publication/pinning, model and isolation qualification, and desktop gateway qualification after those dependencies resolve. Source remains uncommitted. Recovery before deployment is removal of this slice's two configuration additions; no runtime rollback is necessary.
