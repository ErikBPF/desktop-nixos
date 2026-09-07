# Apollo NIC recovery

**Status:** Delivered — generation 15 reboot proved automatic NIC naming, DHCP, guest NAT and five-node recovery.

The diagnosis and rollout below record the completed September 7 recovery.
The current interface is `lan0`; `enp5s0` was its pre-repair name. No additional
staging or reboot is needed for this documentation closeout.

## Historical diagnosis

Reuse the already-trusted LAN host key through `HostKeyAlias`; do not bypass
host-key verification. Use Apollo's fleet-declared Tailscale address when its LAN reservation is
unreachable. Read applied link configuration before choosing the source fix:

```bash
ssh -p 2222 -o 'HostKeyAlias=[192.168.10.174]:2222' -o BatchMode=yes -o ConnectTimeout=8 erik@100.77.14.27 \
  'hostname; readlink -f /run/current-system; uname -r
   ip -br link; ip -br address; ip route
   networkctl list --no-pager
   systemctl --failed --no-pager
   journalctl -b -u systemd-networkd -u systemd-networkd-wait-online --no-pager -n 100
   for device in /sys/class/net/*; do
     printf "%s address=%s device=%s\n" "${device##*/}" "$(cat "$device/address")" "$(readlink -f "$device/device")"
   done'
```

Read udev identity and the hardware address before selecting the link match:

```bash
ssh -p 2222 -o 'HostKeyAlias=[192.168.10.174]:2222' -o BatchMode=yes -o ConnectTimeout=8 erik@100.77.14.27 \
  'udevadm info --query=property --path=/sys/class/net/enp5s0
   ethtool -P enp5s0
   nvidia-smi --query-gpu=name,driver_version,power.limit --format=csv,noheader
   systemctl status nvidia-conservative-clocks --no-pager -n 12'
```

## Observed cause and repair

The GPU exchange moved the Realtek RTL8111/8168 PCI function from bus 6 to bus 5.
Its automatically generated name changed from `enp6s0` to `enp5s0`; DHCP and k3s
NAT still referenced the missing name. The real NIC was unmanaged, with IPv6
SLAAC but no IPv4 address or default IPv4 route. IPv6 kept Tailscale available.
`ethtool -P` confirms permanent MAC `2a:38:4d:07:de:54`, matching fleet metadata.

Bind `lan0` to that permanent MAC with an early systemd `.link`. One local
interface constant supplies the link name, DHCP owner and NAT egress. Keep
NetworkManager disabled and preserve the existing k3s bridge and guest placement.
No polling service, restart loop or second DHCP client is needed.

## Historical rollout and acceptance

Run the effective network contract, lint/format/docs checks and `just dry apollo`
plus `just build apollo`; publish and pass CI before staging. Reach the existing
owner's deploy-rs entry point over the alternate fleet address, retaining its
builder configuration and trusted host key:

```bash
BUILDERS="$(just _builders apollo)"
nix run .#deploy-rs -- --skip-checks --boot --fast-connection true \
  --hostname 100.77.14.27 \
  --ssh-opts '-p 2222 -o HostKeyAlias=[192.168.10.174]:2222' .#apollo \
  -- --option builders "$BUILDERS" --option builders-use-substitutes true --max-jobs 0
```

Verify the new default and original generation 14 before one controlled reboot:

```bash
ssh -p 2222 -o 'HostKeyAlias=[192.168.10.174]:2222' -o BatchMode=yes -o ConnectTimeout=8 erik@100.77.14.27 \
  'readlink -f /run/current-system; readlink -f /nix/var/nix/profiles/system; sudo bootctl list --no-pager'
ssh -p 2222 -o 'HostKeyAlias=[192.168.10.174]:2222' -o BatchMode=yes -o ConnectTimeout=8 erik@100.77.14.27 \
  'sudo systemd-run --collect --on-active=2s systemctl reboot'
```

Observe SSH go down and return. Then verify over the original LAN reservation:

```bash
ssh -p 2222 -o BatchMode=yes -o ConnectTimeout=8 erik@192.168.10.174 \
  'readlink -f /run/current-system; uname -r
   ip -br address; ip route; networkctl status lan0 --no-pager
   systemctl --failed --no-pager
   sudo iptables -t nat -S nixos-nat-post
   nvidia-smi --query-gpu=name,driver_version,power.limit --format=csv,noheader'
just diagnose-apollo-worklab
kubectl --context apollo-dev get nodes -o wide
```

Require automatic `lan0` configuration with the expected MAC, DHCP reservation
`192.168.10.174`, default IPv4 route, guest NAT via `lan0`, all five cluster nodes
Ready, retained NVIDIA limits, mounted `/mnt/nfs/fast` and `/mnt/nfs/bulk`, and
no failed units (including the previously failed wait-online and NFS mounts). Household inference stays
paused. Keep the prior generation until this reboot acceptance passes; it retains
the old NIC failure and is recovery fallback, not a successful networking fix.

## Completed acceptance — 2026-09-07

[Desktop #296](https://github.com/ErikBPF/desktop-nixos/pull/296) merged as
`eff62b6` after effective-option RED/GREEN checks, matching rendered initrd and
system link rules, full build, independent review and green CI. The controlled
reboot booted generation **15**. At **20:35:51 UTC**, networkd automatically
acquired `192.168.10.174/24` with gateway `192.168.10.1` on `lan0`, using
`10-apollo-lan.link`, `40-lan0.network` and permanent MAC `2a:38:4d:07:de:54`.
No manual NIC command was needed after boot. Guest NAT used `lan0`, all five
nodes were Ready, both NFS shares were mounted, and no host units failed.

Generation 14 was the temporary rollback entry during this repair. The later
[GPU acceptance and retention cleanup](kepler-apollo-gpu-exchange.md) supersedes
that ledger: at **21:20:53 UTC**, exactly generations **15–17** remained,
accepted generation **15** still running and **17** the next-boot default.
No further reboot occurred; household inference remains paused.
