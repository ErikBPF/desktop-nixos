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


def test_apollo_runs_a_small_rebuildable_k3s_cluster() -> None:
    cluster = read("modules/hosts/apollo/k3s-cluster.nix")

    assert '../../services/_k3s-node.nix' in cluster
    assert 'hypervisor = "cloud-hypervisor";' in cluster
    assert 'workerCount = 2;' in cluster
    assert 'workerMem = 16384;' in cluster
    assert 'subnet = "10.251.0";' in cluster


def test_apollo_uses_the_observed_lan_interface() -> None:
    network = read("modules/hosts/apollo/networking.nix")

    assert 'hostName = "apollo";' in network
    assert 'enp6s0' in network
