from pathlib import Path


ROOT = Path(__file__).parents[2]


def test_kepler_persists_crash_evidence_and_recovers_from_lockups():
    kepler = (ROOT / "modules/hosts/kepler/default.nix").read_text()
    power = (ROOT / "modules/hardware/power-desktop.nix").read_text()
    boot = (ROOT / "modules/hardware/systemd-boot-counting.nix").read_text()

    for setting in (
        "Storage=persistent",
        "SystemMaxUse=2G",
        '"kernel.watchdog" = 1;',
        '"kernel.nmi_watchdog" = lib.mkForce 1;',
        '"kernel.softlockup_panic" = 1;',
        '"kernel.hardlockup_panic" = 1;',
        '"kernel.watchdog_thresh" = 30;',
    ):
        assert setting in kepler

    assert '"kernel.nmi_watchdog" = 0;' in power
    assert 'boot.kernelParams = ["panic=10"];' in boot


def test_kepler_host_and_guests_use_the_fleet_linux_7_2_kernel():
    kepler = (ROOT / "modules/hosts/kepler/default.nix").read_text()
    server = (ROOT / "modules/profiles/server.nix").read_text()
    cluster = (ROOT / "modules/hosts/kepler/k3s-cluster.nix").read_text()

    assert "boot.kernelPackages" not in kepler
    assert "boot.kernelPackages = pkgs.linuxPackages_7_2;" in server
    assert "boot.kernelPackages = pkgs.linuxPackages_7_2;" in cluster


def test_kepler_holds_unattended_mutation_during_stability_incident():
    kepler = (ROOT / "modules/hosts/kepler/default.nix").read_text()
    upgrade = kepler.split("system.autoUpgrade = {", 1)[1].split("};", 1)[0]

    assert "enable = false;" in upgrade
    assert "nix.gc.automatic = lib.mkForce false;" in kepler
