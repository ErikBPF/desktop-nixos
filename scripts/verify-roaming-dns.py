#!/usr/bin/env python3
"""Read-only off-LAN DNS/HTTPS acceptance probe."""

import argparse
import ipaddress
import json
from pathlib import Path
import subprocess


def run(argv):
    return subprocess.run(
        argv, check=True, capture_output=True, text=True, timeout=12
    ).stdout.strip()


def require(condition, message):
    if not condition:
        raise ValueError(message)


def off_lan(home):
    routes = json.loads(run(["ip", "-j", "-4", "route", "show", "table", "main"]))
    addresses = json.loads(run(["ip", "-j", "-4", "address", "show"]))
    active = [i for i in addresses if "UP" in i.get("flags", ["UP"])
              and i.get("operstate") != "DOWN"]
    inactive = {i["ifname"] for i in addresses if i not in active}
    for interface in active:
        if interface["ifname"] == "tailscale0":
            continue
        for address in interface["addr_info"]:
            if address.get("family") == "inet":
                subnet = ipaddress.IPv4Network(
                    f"{address['local']}/{address['prefixlen']}", strict=False)
                require(not subnet.overlaps(home), "active non-Tailscale address overlaps home LAN")
    connected = []
    for route in routes:
        dev = route.get("dev", "")
        if (dev == "tailscale0" or dev in inactive or route.get("dst") == "default"
                or (route.get("scope") != "link" and "gateway" in route)
                or "linkdown" in route.get("flags", [])
                or "dst" not in route):
            continue
        subnet = ipaddress.IPv4Network(route["dst"])
        require(not subnet.overlaps(home), "non-Tailscale connected route overlaps home LAN")
        if not (Path("/sys/class/net") / dev / "device").exists():
            continue
        for interface in active:
            if interface["ifname"] != dev:
                continue
            for address in interface["addr_info"]:
                if address.get("family") == "inet" and address.get("scope") == "global":
                    source = ipaddress.IPv4Address(address["local"])
                    if source in subnet:
                        require(route.get("prefsrc", str(source)) == str(source),
                                "ambiguous physical source")
                        connected.append((dev, subnet, source))
    require(len(connected) == 1, "need one unambiguous physical connected subnet/source")
    dev, subnet, source = connected[0]
    defaults = [r for r in routes if r.get("dst") == "default"]
    require(len(defaults) == 1 and defaults[0].get("dev") == dev
            and ipaddress.IPv4Address(defaults[0].get("gateway", "0.0.0.0")) in subnet
            and defaults[0].get("prefsrc", str(source)) == str(source),
            "need matching physical main-table default")
    print(f"OFF_LAN_VERIFIED dev={dev} source={source} subnet={subnet}")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--off-lan", action="store_true", help="explicit roaming-test intent")
    args = parser.parse_args(argv)
    if not args.off_lan:
        print("ROAMING_DNS_UNAVAILABLE: require explicit --off-lan intent")
        return 2
    confirmed = False
    stage = "environment"
    try:
        fleet = json.loads((Path(__file__).resolve().parents[1] / "fleet.json").read_text())
        discovery = fleet["hosts"]["discovery"]
        ip = str(ipaddress.IPv4Address(discovery["ip"]))
        tail = str(ipaddress.IPv4Address(discovery["tailscaleIp"]))
        zone = fleet["ingress"]["homelab"]["zone"]
        require(fleet["ingress"]["homelab"]["host"] == "discovery", "ingress owner changed")
        home = ipaddress.IPv4Network(f"{ip}/24", strict=False)
        off_lan(home)
        confirmed = True
        prefixes = [f"{home[n]}/32" for n in (1, 2, 4)] + [f"{ip}/32"]
        stage = "peer-identity"
        status = json.loads(run(["tailscale", "status", "--json"]))
        identities = [p for p in status["Peer"].values() if tail in p.get("TailscaleIPs", [])]
        require(len(identities) == 1 and identities[0].get("HostName") == "discovery",
                "stable tailnet IP must identify HostName discovery")
        stage = "peer-allowed-ips"
        try:
            netmap = run(["tailscale", "debug", "netmap"])
        except subprocess.CalledProcessError:
            sudo = "/run/wrappers/bin/sudo" if Path("/run/wrappers/bin/sudo").exists() else "sudo"
            netmap = run([sudo, "-n", "tailscale", "debug", "netmap"])
        peers = [p for p in json.loads(netmap)["Peers"] if f"{tail}/32" in p["Addresses"]]
        require(len(peers) == 1 and set(prefixes) <= set(peers[0]["AllowedIPs"]),
                "Discovery peer lacks required /32 AllowedIPs")
        for prefix in prefixes:
            stage = f"route-{prefix}"
            route = json.loads(run(["ip", "-j", "-4", "route", "get", prefix.split("/")[0]]))
            require(len(route) == 1 and route[0].get("dev") == "tailscale0",
                    "route must use tailscale0")
        name = f"litellm.{zone}"
        for transport in ("+notcp", "+tcp"):
            stage = f"dns-{transport[1:]}"
            answer = run(["dig", f"@{ip}", name, "A", "+short", "+time=3",
                          "+tries=1", "+ignore", transport])
            require(answer.splitlines() == [ip], "DNS A answer must equal Discovery LAN IP")
        for host in ("litellm", "adguard"):
            stage = f"system-dns-{host}"
            answer = run(["getent", "ahostsv4", f"{host}.{zone}"])
            require({line.split()[0] for line in answer.splitlines()} == {ip},
                    "system IPv4 resolution must equal Discovery LAN IP")
        for host, path, status in (("litellm", "/v1/models", "401"), ("adguard", "/", "302")):
            stage = f"https-{host}"
            result = run(["curl", "--disable", "--silent", "--show-error", "--ipv4",
                          "--noproxy", "*", "--connect-timeout", "3", "--max-time", "8",
                          "--output", "/dev/null", "--write-out", "%{http_code} %{remote_ip}",
                          f"https://{host}.{zone}{path}"])
            require(result.split() == [status, ip], "unexpected HTTP status or remote IP")
            print(f"HTTPS_VERIFIED host={host} status={status} remote_ip={ip}")
    except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError) as error:
        marker = "ROAMING_DNS_FAILED" if confirmed else "ROAMING_DNS_UNAVAILABLE"
        # No command stderr/netmap/body output: those may contain private state.
        reason = str(error) if isinstance(error, ValueError) and not isinstance(error, json.JSONDecodeError) else type(error).__name__
        print(f"{marker} stage={stage}: {reason}")
        return 1 if confirmed else 2
    print("ROAMING_DNS_OK: off-LAN routes, DNS and TLS-verified HTTPS passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
