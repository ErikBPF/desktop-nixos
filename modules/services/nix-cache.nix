_: {
  flake.modules.nixos.nix-cache = {
    config,
    pkgs,
    ...
  }: {
    services.nix-serve = {
      enable = true;
      bindAddress = "127.0.0.1";
      port = 5000;
      secretKeyFile = "/etc/nix/cache-priv-key.pem";
    };

    services.nginx = {
      enable = true;
      recommendedProxySettings = true;
      recommendedTlsSettings = true;
      virtualHosts."nix-cache.homelab.pastelariadev.com" = {
        forceSSL = true;
        sslCertificate = "/var/lib/nix-cache/tls/cert.pem";
        sslCertificateKey = "/var/lib/nix-cache/tls/key.pem";
        locations."/" = {
          proxyPass = "http://127.0.0.1:${toString config.services.nix-serve.port}";
        };
      };
    };

    # Generate self-signed TLS cert if none exists (operator can replace with
    # a tailscale cert or ACME DNS-01 cert later)
    systemd.services.nix-cache-tls-init = {
      description = "Generate self-signed TLS cert for nix-cache";
      wantedBy = ["multi-user.target"];
      before = ["nginx.service"];
      requiredBy = ["nginx.service"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      path = [pkgs.openssl];
      script = ''
        CERT_DIR=/var/lib/nix-cache/tls
        if [ ! -f "$CERT_DIR/cert.pem" ]; then
          mkdir -p "$CERT_DIR"
          openssl req -x509 -newkey rsa:4096 \
            -keyout "$CERT_DIR/key.pem" \
            -out "$CERT_DIR/cert.pem" \
            -days 365 -nodes \
            -subj "/CN=nix-cache.homelab.pastelariadev.com"
          chmod 600 "$CERT_DIR/key.pem"
        fi
      '';
    };

    # Daily closure builder — keeps the cache warm
    systemd.services.nix-cache-builder = {
      description = "Build all host closures to warm the nix cache";
      serviceConfig = {
        Type = "oneshot";
        WorkingDirectory = "/var/lib/nix-cache-builder/repo";
      };
      path = [pkgs.git pkgs.nix pkgs.nixos-rebuild];
      script = ''
        set -euo pipefail
        echo ":: Pulling latest from main..."
        git pull --ff-only origin main

        echo ":: Building host closures..."
        nix build .#nixosConfigurations.pathfinder.config.system.build.toplevel --no-link
        nix build .#nixosConfigurations.discovery.config.system.build.toplevel --no-link

        echo ":: Cache builder complete"
      '';
    };

    systemd.timers.nix-cache-builder = {
      description = "Daily nix cache builder timer";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnCalendar = "03:00";
        Persistent = true;
      };
    };

    # Only allow cache traffic on the tailscale interface
    networking.firewall.interfaces.tailscale0.allowedTCPPorts = [443];
  };
}
