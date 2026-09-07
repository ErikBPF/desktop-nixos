from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def read(relative: str) -> str:
    path = ROOT / relative
    assert path.exists(), f"missing {relative}"
    return path.read_text()


def test_apollo_is_a_deployable_fleet_server() -> None:
    meta = read("modules/meta.nix")
    deploy = read("modules/deploy-rs.nix")

    assert 'apollo = {' in meta
    assert 'ip = "192.168.10.174";' in meta
    assert 'mac = "2a:38:4d:07:de:54";' in meta
    assert 'tailscaleIp = "100.77.14.27";' in meta
    assert 'apollo = mkNode {' in deploy


def test_apollo_uses_the_observed_os_disks() -> None:
    hardware = read("modules/hosts/apollo/hardware.nix")

    assert "ata-KINGSTON_SA400S37240G_50026B7783B9EE25" in hardware
    assert "ata-KINGSTON_SA400S37240G_50026B76831D2524" in hardware
    assert hardware.count('"raid1"') == 2


def test_apollo_runs_the_accepted_rebuildable_k3s_cluster() -> None:
    cluster = read("modules/hosts/apollo/k3s-cluster.nix")

    assert '../../services/_k3s-node.nix' in cluster
    assert 'hypervisor = "cloud-hypervisor";' in cluster
    assert 'workerCount = 2;' in cluster
    assert 'workerMem = 32768;' in cluster
    assert 'mem = 8192;' in cluster
    assert 'subnet = "10.251.0";' in cluster


def test_apollo_keeps_guest_state_on_root_and_bounds_build_concurrency() -> None:
    hardware = read("modules/hosts/apollo/hardware.nix")
    host = read("modules/hosts/apollo/default.nix")
    assert 'mountpoint = "/mnt/microvms";' in hardware
    assert 'mountpoint = "/var/lib/microvms";' not in hardware
    assert 'max-jobs = lib.mkForce 6;' in host
    assert 'cores = lib.mkForce 2;' in host


def test_orion_reinstall_uses_stable_disks_and_preserves_work_sessions() -> None:
    hardware = read("modules/hosts/orion/hardware.nix")
    host = read("modules/hosts/orion/default.nix")
    for disk in (
        "nvme-Force_MP510_19458242000129183963",
        "ata-KINGSTON_SV300S37A480G_50026B724709FD21",
        "ata-SanDisk_SSD_PLUS_480GB_193181805834",
    ):
        assert f'device = "/dev/disk/by-id/{disk}";' in hardware
    assert 'operation = "boot";' in host
    assert 'allowReboot = false;' in host


def test_apollo_uses_the_observed_lan_interface() -> None:
    network = read("modules/hosts/apollo/networking.nix")

    assert 'hostName = "apollo";' in network
    assert 'uplink = "lan0";' in network
    assert 'interfaces.${uplink}.useDHCP = true;' in network
    assert 'nat.externalInterface = uplink;' in network
    assert 'matchConfig.PermanentMACAddress = config.flake.fleet.hosts.apollo.mac;' in network


def test_apollo_nfs_uses_its_reachable_lan_path() -> None:
    client = read("modules/services/kepler-nfs.nix")
    server = read("modules/hosts/kepler/nas.nix")

    assert 'config.networking.hostName == "apollo"' in client
    assert 'fleet.hosts.kepler.ip' in client
    assert 'config.fleet.hosts.apollo.ip' in server


def test_deployment_can_recover_over_tailnet() -> None:
    import subprocess

    for recipe in ("deploy-rs", "deploy-rs-preview"):
        command = subprocess.run(
            ["just", "--dry-run", recipe, "apollo", "apollo"],
            cwd=ROOT, capture_output=True, text=True,
        )
        assert command.returncode == 0, command.stderr
        assert "--hostname 'apollo'" in command.stderr
