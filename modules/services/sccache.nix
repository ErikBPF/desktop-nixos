{config, ...}: let
  inherit (config) fleet;
  orionTs = fleet.hosts.orion.tailscaleIp;
  cachePort = 4321;
in {
  # Shared sccache compiler cache for dev-loop `cargo build`, disk-backed on
  # orion and reached over the tailnet. Server = nginx WebDAV; clients set
  # RUSTC_WRAPPER=sccache + SCCACHE_WEBDAV_ENDPOINT. In cache mode sccache still
  # runs rustc *locally* — orion only stores/serves cached objects — so a cache
  # miss or an unreachable orion (off-tailnet, DNS fail, timeout) transparently
  # falls back to a local compile. Nix builds are sandboxed and ignore
  # RUSTC_WRAPPER, so the Nix build-offload path (distributed-builds.nix) is
  # untouched; this only affects interactive cargo.
  flake.modules.nixos.sccache-cache = {
    config,
    lib,
    ...
  }: {
    options.services.sccacheCache.enable =
      lib.mkEnableOption "host a shared sccache WebDAV cache on the tailnet";

    config = lib.mkIf config.services.sccacheCache.enable {
      systemd.tmpfiles.rules = ["d /var/cache/sccache-shared 0750 nginx nginx -"];

      services.nginx = {
        enable = true;
        # http_dav_module is compiled into nixpkgs' default nginx.
        virtualHosts."sccache-cache" = {
          # Listen on all interfaces; 4321 is opened *only* on tailscale0 by the
          # firewall rule below, so LAN/WAN can't reach it. Binding 0.0.0.0
          # (rather than orionTs) sidesteps the tailscale0 IP-assignment boot
          # race that forces the retry loop in discovery/vault.nix.
          listen = [
            {
              addr = "0.0.0.0";
              port = cachePort;
            }
          ];
          locations."/" = {
            root = "/var/cache/sccache-shared";
            extraConfig = ''
              client_max_body_size 1024m;
              dav_methods PUT DELETE MKCOL COPY MOVE;
              dav_access user:rw group:rw all:r;
              create_full_put_path on;
              autoindex off;
            '';
          };
        };
      };

      networking.firewall.interfaces.tailscale0.allowedTCPPorts = [cachePort];
    };
  };

  flake.modules.nixos.sccache-client = {
    config,
    lib,
    pkgs,
    ...
  }: {
    options.programs.sccacheClient.enable =
      lib.mkEnableOption "route dev-loop cargo builds through the shared sccache cache on orion";

    config = lib.mkIf config.programs.sccacheClient.enable {
      assertions = [
        {
          assertion = orionTs != null;
          message = "programs.sccacheClient needs fleet.hosts.orion.tailscaleIp set in modules/meta.nix.";
        }
      ];
      environment.systemPackages = [pkgs.sccache];
      # Applies to login shells (re-login after switch to pick it up). Nix's own
      # sandboxed builds ignore this, so only interactive cargo is affected.
      environment.sessionVariables = {
        RUSTC_WRAPPER = "sccache";
        SCCACHE_WEBDAV_ENDPOINT = "http://${orionTs}:${toString cachePort}/";
      };
    };
  };
}
