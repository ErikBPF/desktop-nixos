{config, ...}: let
  uplink = "lan0";
in {
  flake.modules.nixos.apollo-networking = {lib, ...}: {
    networking = {
      hostName = "apollo";
      networkmanager.enable = false;
      useDHCP = false;
      interfaces.${uplink}.useDHCP = true;
      firewall = {
        enable = true;
        checkReversePath = "loose";
        # apollo-ai exposes vLLM and pqnld only to discovery over tailscale0.
        # The unit preflight asserts these exact rules before starting.
        extraCommands = ''
          iptables -N apollo-qwen-litellm 2>/dev/null || true
          iptables -F apollo-qwen-litellm
          iptables -A apollo-qwen-litellm -i lo -j ACCEPT
          iptables -A apollo-qwen-litellm -s ${config.flake.fleet.hosts.discovery.tailscaleIp}/32 -i tailscale0 -p tcp -m multiport --dports 11542,11560 -j ACCEPT
          iptables -A apollo-qwen-litellm -j REJECT --reject-with icmp-port-unreachable
        '';
        extraInputRules = ''
          iptables -A INPUT -d ${config.flake.fleet.hosts.apollo.tailscaleIp}/32 -p tcp -m tcp --dport 11542 -j apollo-qwen-litellm
          iptables -A INPUT -d ${config.flake.fleet.hosts.apollo.tailscaleIp}/32 -p tcp -m tcp --dport 11560 -j apollo-qwen-litellm
        '';
      };
    };

    # Keep DHCP independent of PCI numbering after hardware moves.
    systemd.network.links."10-apollo-lan" = {
      matchConfig.PermanentMACAddress = config.flake.fleet.hosts.apollo.mac;
      linkConfig = {
        NamePolicy = "";
        Name = uplink;
        WakeOnLan = "magic";
      };
    };

    services.tailscale = {
      useRoutingFeatures = lib.mkForce "client";
      extraSetFlags = lib.mkForce ["--accept-dns=true" "--accept-routes=false"];
    };
  };
}
