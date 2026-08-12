# Endeavour Trend Micro test contract

**Status:** Migrated

- Endeavour and Pathfinder contain no NixOS WARP, KACE, or Trend Micro units.
- NixOS does not open Trend Micro manager port `4118`.
- The Ubuntu work VM owns the vendor packages through apt/dpkg.
- Guest deployment is healthy only when WARP, KACE, Deep Security Agent, and
  Endpoint Basecamp services are active.
