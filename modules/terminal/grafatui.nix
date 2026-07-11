_: {
  # grafatui — Prometheus/Grafana metrics TUI (fedexist/grafatui, crates.io).
  # Package comes from the modules/overlays.nix buildRustPackage derivation.
  # The `fleet-metrics` launcher presets the fleet Prometheus endpoint
  # (Alloy remote-write receiver at discovery:9090 over the tailnet, MagicDNS)
  # and imports a pinned snapshot of servarr's `fleet-status` Grafana dashboard
  # (gate G5). The JSON is vendored under _grafatui/ (D9 publish-and-pin — the
  # dashboard's SSOT is servarr; re-copy on change). Needs the tailnet ACL
  # grant laptop -> discovery:9090 (gate G4, applied in homelab-iac).
  flake.modules.home.grafatui = {pkgs, ...}: {
    home.packages = [
      pkgs.grafatui
      (pkgs.writeShellScriptBin "fleet-metrics" ''
        exec ${pkgs.grafatui}/bin/grafatui \
          --prometheus-url http://discovery:9090 \
          --grafana-json ${./_grafatui/fleet-status.json} "$@"
      '')
    ];
  };
}
