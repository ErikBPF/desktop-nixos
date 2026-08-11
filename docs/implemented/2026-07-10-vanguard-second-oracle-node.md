# vanguard — second Oracle free VM

**Status:** Implemented — CoreDNS secondary and external dead-man probe live;
Vault witness deferred.

`vanguard` is the second Oracle Always-Free x86 micro in São Paulo. It is a
small offsite resilience host, not an independent geographic failure domain.

## Live roles

- `services.fleetDns`: CoreDNS secondary bound to `tailscale0`, registered as a
  fallback resolver in the Tailscale control plane.
- `services.deadMansSwitch`: independent systemd timer probing the public Home
  Assistant endpoint and sending alerts through its own Discord webhook.
- Hardened SSH on port 2222 plus Tailscale for break-glass access.

## Deferred role

`services.vaultWitness` remains disabled. Enabling it requires a WAN-latency
test plus an explicit OpenBao quorum and TLS design; the current one-node Vault
configuration is unchanged.

## Host constraints

- Oracle `VM.Standard.E2.1.Micro`: 1 OCPU, 1 GB RAM, 4 GB swap.
- Ephemeral public IP; Tailscale is the stable management path.
- Provisioned through `just infect-vanguard`; deployed through
  `just switch-vanguard`.
- Oracle block volumes do not expose SMART, so `smartd` is disabled.

## Owned artifacts

- `modules/hosts/vanguard/{default,hardware,networking}.nix`
- `modules/services/{fleet-dns,dead-mans-switch,vault-witness}.nix`
- `homelab-iac` Oracle compute plus Tailscale DNS/ACL resources

The same-provider VM is useful for resolver and alert-egress redundancy, but it
does not qualify as a separate 3-2-1 backup tier.
