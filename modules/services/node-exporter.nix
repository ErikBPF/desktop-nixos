# Lightweight host metrics for hosts too small for Alloy (~260 MB RSS — the
# reason archinaut skips it; voyager is the same 1 GB class): plain
# node_exporter (~20 MB), scraped by discovery Prometheus over the tailnet
# (pull — Alloy hosts push via remote_write instead). Bind-all + tailscale0-only
# firewall sidesteps the boot race of binding a not-yet-up tailnet IP (same
# pattern as sccache.nix). Tailnet ACL: discovery -> *:* already covers the
# scrape; nothing to open in homelab-iac.
_: {
  flake.modules.nixos.node-exporter = _: {
    services.prometheus.exporters.node = {
      enable = true;
      port = 9100;
      listenAddress = "0.0.0.0";
      # `systemd` (disabled by default) emits node_systemd_unit_state so the
      # failed-unit alert (servarr grafana rule host-systemd-unit-failed) can see
      # these small hosts too — the Alloy hosts get it via prometheus.exporter.unix
      # (alloy.nix). Fleet upgrade hardening RFC P2 (2026-07-12): netbird-management
      # crash-looped ~8h and LACT was failed ~20m with zero alerts.
      enabledCollectors = ["systemd"];
    };

    networking.firewall.interfaces.tailscale0.allowedTCPPorts = [9100];
  };
}
