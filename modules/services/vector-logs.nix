_: {
  # Lite journal→Loki shipper for storage/RAM-constrained hosts (e.g. the 1 GB
  # archinaut printer Pi) where the full Alloy agent is too heavy (~260 MB RSS
  # starved sshd during boot — see modules/services/alloy.nix). Vector idles at
  # ~30-60 MB and ships the same journal stream, so these hosts show up in the
  # fleet Logs dashboard next to Alloy hosts.
  #
  # Deliberately logs-only: no metrics scrape (that stays with Alloy on the
  # hosts that can afford it). Schema matches Alloy's loki.source.journal —
  # labels { source = "journal", host = <hostName> } — so the streams line up.
  flake.modules.nixos.vector-logs = {config, ...}: {
    services.vector = {
      enable = true;
      journaldAccess = true;
      settings = {
        # No GraphQL playground / API — trims footprint and attack surface.
        api.enabled = false;

        sources.journal = {
          type = "journald";
          # Ship prior-boot logs too: the whole point here is post-mortem after
          # a host goes dark. Vector checkpoints the journal cursor in its
          # data_dir, so a restart resumes rather than re-shipping.
          current_boot_only = false;
        };

        sinks.loki = {
          type = "loki";
          inputs = ["journal"];
          # Discovery's Loki over Tailscale MagicDNS (requires accept-dns +
          # tailnet ACL host -> discovery:3100, same as Alloy hosts). Vector
          # appends /loki/api/v1/push to this base endpoint itself.
          endpoint = "http://discovery:3100";
          # Match the fleet Alloy label set exactly (build-time hostname bake —
          # mirrors the alloy.nix journal labels).
          labels = {
            source = "journal";
            host = config.networking.hostName;
          };
          # Ship the raw journal message line (the `text` codec emits .message).
          encoding.codec = "text";
        };
      };
    };
  };
}
