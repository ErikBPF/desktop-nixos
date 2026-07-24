# Kepler fast state test contract

**Status:** Implemented

- `microvm.stateDir` evaluates to `/fast/microvms`.
- MicroVM units require that path to be mounted.
- Migration copies sparse images and AI state, then checksum-verifies.
- Source copies remain until k3s nodes, bootstrap, observability, and alerts pass.
