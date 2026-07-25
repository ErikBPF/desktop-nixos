# Endeavour Trend Micro test contract

**Status:** Active

- Endeavour evaluates with a host-scoped Trend Micro module.
- Installer credentials never enter the Nix store or Git plaintext.
- Installer runs once, only while Endpoint Basecamp identity is absent.
- Ubuntu compatibility spoof is limited to installer execution.
- Deployment is healthy only when `ds_agent` is active and Endpoint Basecamp
  has registered.
