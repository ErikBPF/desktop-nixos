_: {
  # Fleet exception to NetBird retirement (2026-08-10, homelab
  # docs/decisions/2026-08-10-pangolin-netbird-retirement.md): this is a
  # *client* for an external, non-fleet network only. No self-hosted control
  # plane, no fleet enrollment, no fleet secrets. Enrollment is interactive
  # (`netbird up`) by the user; nothing here connects to homelab infrastructure.
  flake.modules.nixos.netbird-client = {
    services.netbird.enable = true;
  };
}
