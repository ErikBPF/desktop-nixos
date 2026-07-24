from pathlib import Path


SSH_MODULE = Path(__file__).parents[2] / "modules/ssh.nix"


def test_nixos_fleet_hosts_default_to_hardened_ssh_port():
    text = SSH_MODULE.read_text()
    fleet_hosts = {
        "archinaut",
        "discovery",
        "endeavour",
        "kepler",
        "orion",
        "pathfinder",
        "telstar",
        "vanguard",
        "voyager",
    }

    host_line = next(
        line.strip()
        for line in text.splitlines()
        if line.strip().startswith("Host ") and "discovery" in line.split()
    )
    assert fleet_hosts <= set(host_line.split()[1:])
    block = text.split(host_line, 1)[1].split("\n\n", 1)[0]
    assert "Port 2222" in block
    assert "User erik" in block


def test_read_only_config_is_replaced_atomically():
    text = SSH_MODULE.read_text()
    assert "mktemp ~/.ssh/config.XXXXXX" in text
    assert 'mv -f "$config_tmp" ~/.ssh/config' in text
