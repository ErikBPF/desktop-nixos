import json
from pathlib import Path


def read(path: str) -> str:
    return Path(path).read_text()


def test_endeavour_moves_work_posture_into_the_vm():
    endeavour = read("modules/hosts/endeavour/default.nix")

    assert "m.nixos.work" not in endeavour
    assert "m.nixos.endeavour-ubuntu-work" in endeavour
    assert "cloudflare-warp" not in endeavour
    assert "boot.kernelPackages = pkgs.linuxPackages_latest;" in endeavour
    assert 'environment.etc."brave/policies/managed/cloudflare-access.json"' not in endeavour


def test_endeavour_owns_the_ubuntu_work_vm_definition():
    endeavour = read("modules/hosts/endeavour/default.nix")
    module = read("modules/hosts/endeavour/ubuntu-work.nix")

    assert "m.nixos.endeavour-ubuntu-work" in endeavour
    assert "flake.modules.nixos.endeavour-ubuntu-work" in module
    assert 'environment.etc."libvirt/qemu/ubuntu-work.xml"' in module
    assert "$VIRSH define /etc/libvirt/qemu/ubuntu-work.xml" in module
    assert "$VIRSH autostart --disable ubuntu-work" in module
    assert "$VIRSH start ubuntu-work" not in module.split("systemd.services.ubuntu-work-vm", 1)[1]
    assert "$VIRSH destroy ubuntu-work" not in module
    assert "nstech-tools.iso 0600 root root" in module


def test_ubuntu_work_vm_preserves_identity_and_post_install_boot():
    domain = read("modules/hosts/endeavour/ubuntu-work-domain.xml")

    assert "<name>ubuntu-work</name>" in domain
    assert "5e9e7f25-eaa8-486c-ab59-d4ef89f19841" in domain
    assert "52:54:00:3d:d6:e9" in domain
    assert "pc-q35-11.0" in domain
    assert "name='secure-boot'" in domain
    assert "name='enrolled-keys'" in domain
    assert "version='2.0'" in domain
    assert "<boot dev='hd'/>" in domain
    assert "/var/lib/libvirt/images/ubuntu-work.qcow2" in domain
    assert "/var/lib/libvirt/images/nstech-tools.iso" in domain
    assert "<readonly/>" in domain
    assert "ubuntu-24.04.4-desktop-amd64.iso" not in domain


def test_ubuntu_work_vm_is_sized_as_an_always_available_browser():
    domain = read("modules/hosts/endeavour/ubuntu-work-domain.xml")

    assert "<memory unit='MiB'>8192</memory>" in domain
    assert "<vcpu placement='static'>4</vcpu>" in domain
    assert "<on_poweroff>restart</on_poweroff>" in domain
    assert "<on_crash>restart</on_crash>" in domain
    assert "<watchdog model='itco' action='reset'/>" in domain
    assert "<suspend-to-mem enabled='no'/>" in domain
    assert "<suspend-to-disk enabled='no'/>" in domain


def test_ubuntu_work_vm_has_stable_ssh_and_viewer_entrypoints():
    module = read("modules/hosts/endeavour/ubuntu-work.nix")

    assert "192.168.122.74" in module
    assert "52:54:00:3d:d6:e9" in module
    assert "$VIRSH net-update default add-last ip-dhcp-host" in module
    assert "Host ubuntu-work" in module
    assert "HostName 192.168.122.74" in module
    assert "ubuntu-work-view" in module
    assert "--reconnect --auto-resize=always --attach ubuntu-work" in module
    assert "$VIRSH start ubuntu-work" not in module.split("systemd.services.ubuntu-work-vm", 1)[1]


def test_ubuntu_work_browser_opens_from_endeavour():
    module = read("modules/hosts/endeavour/ubuntu-work.nix")
    hyprland = read("modules/desktop/hyprland.nix")

    assert 'name = "ubuntu-work-browser";' in module
    assert "start ubuntu-work" in module
    assert "erik@${address}" in module
    assert "pkgs.xpra" in module
    assert "xpra seamless ssh://erik@${address}/" in module
    assert "--ssh=paramiko:agent=no" in module
    assert "XPRA_SOCKET_TIMEOUT=30" in module
    assert "XPRA_SSH_AGENT_AUTH=0" in module
    assert "--remote-xpra=/home/erik/.nix-profile/bin/xpra" in module
    assert "--start-child=/home/erik/.nix-profile/bin/work-browser-xpra" in module
    assert "--exit-with-children=yes" in module
    assert "--exit-with-client=yes" in module
    assert "--resize-display=off:6640x1920" in module
    assert "--desktop-scaling=no" in module
    assert "xpra seamless :100" not in module
    assert "ssh://erik@${address}/100" not in module
    assert "xpra attach" not in module
    assert "xpra list" not in module
    assert "XPRA_CLIPBOARD_CLASS" not in module
    assert "XPRA_CLIPBOARD_CONVERT_TIMEOUT" not in module
    assert "--clipboard=yes" in module
    assert "--clipboard-direction=both" in module
    assert "--keyboard-layout=qwerty-fr" in module
    assert "--keyboard-variant=qwerty-fr" in module
    assert "--xvfb=/home/erik/.nix-profile/bin/work-Xvfb" in module
    assert "xpra _audio_query >/dev/null" in module
    assert "--speaker-codec=opus" in module
    assert "--microphone-codec=opus" in module
    assert "--pulseaudio-command=/home/erik/.nix-profile/bin/work-pulseaudio" in module
    assert "--printing=no" in module
    assert "--webcam=no" in module
    assert "--splash=no" in module
    assert "ubuntu-work-clipboard-push" not in module
    assert "systemd.user.services.ubuntu-work-clipboard" not in module
    assert "exec virt-viewer" not in module.split('name = "ubuntu-work-browser";', 1)[1].split("browserDesktop", 1)[0]
    assert 'desktopName = "Work Browser";' in module
    assert 'class = "^(virt-viewer)$";' in hyprland
    assert r'title = ".* on 192\\.168\\.122\\.74$";' in hyprland
    assert 'workspace = "8 silent";' in hyprland
    assert 'workspace = "9 silent";' in hyprland
    remote_browser_rule = hyprland.split('class = "^(Brave-browser)$";', 1)[1].split('class = "^(chromium)$";', 1)[0]
    assert "float = true;" in remote_browser_rule
    assert 'size = "1920 1080";' in remote_browser_rule


def test_ubuntu_work_spice_carries_audio_mic_and_recovery_channel():
    domain = read("modules/hosts/endeavour/ubuntu-work-domain.xml")

    assert "<sound model='ich9'/>" in domain
    assert "<audio id='1' type='spice'/>" in domain
    assert "name='com.redhat.spice.0'" in domain
    assert "name='org.qemu.guest_agent.0'" in domain


def test_ubuntu_work_has_no_physical_webcam_passthrough():
    domain = read("modules/hosts/endeavour/ubuntu-work-domain.xml")

    assert "<hostdev mode='subsystem' type='usb' managed='yes'>" not in domain
    assert "<vendor id='0x046d'/>" not in domain
    assert "<product id='0x085b'/>" not in domain


def test_ubuntu_work_guest_uses_a_locked_nix_package_profile():
    flake_path = Path("profiles/ubuntu-work/flake.nix")
    lock_path = Path("profiles/ubuntu-work/flake.lock")

    assert flake_path.exists()
    assert lock_path.exists()

    profile = flake_path.read_text()
    lock = json.loads(lock_path.read_text())

    assert "pkgs.buildEnv" in profile
    for package in ["openssh", "tmux", "git", "curl", "jq", "ripgrep", "rsync", "sqlite", "netcat-openbsd", "xpra"]:
        assert package in profile
    assert "xclip" not in profile
    assert 'exec /usr/bin/brave-browser-stable "$@"' in profile
    assert 'writeShellScriptBin "work-browser-xpra"' in profile
    assert "pkill -TERM" not in profile
    assert "--ozone-platform=x11" in profile
    assert "--user-data-dir=$HOME/.config/BraveSoftware/Brave-Browser-Xpra" in profile
    assert "GTK_THEME=Yaru:dark" in profile
    assert "--force-dark-mode" in profile
    assert "ubuntu-work-xpra-display" not in profile
    assert 'writeShellScriptBin "work-Xvfb"' in profile
    assert 'exec /usr/bin/Xvfb "$@"' in profile
    assert 'writeShellScriptBin "work-pulseaudio"' in profile
    assert "module-null-sink sink_name=Xpra-Microphone" in profile
    assert "module-null-sink sink_name=Xpra-Speaker" in profile
    assert "module-remap-source source_name=Xpra-Mic-Input" in profile
    assert profile.index('# Xpra 6.4 classifies Pulse devices using "input"') < profile.index(
        "exec ${pkgs.pulseaudio}"
    )
    assert 'socket="/run/user/$UID/xpra/\'\'${DISPLAY#:}/pulse/native"' in profile
    assert "PULSE_SINK=Xpra-Speaker" in profile
    assert "PULSE_SOURCE=Xpra-Mic-Input" in profile
    assert "--window-size=1920,1080" in profile
    assert "${pkgs.brave}" not in profile
    for apt_owned in ["microsoft-edge", "cloudflare-warp", "ampagent", "ds-agent"]:
        assert apt_owned not in profile
    assert "nixpkgs" in lock["nodes"]
    assert "rev" in lock["nodes"]["nixpkgs"]["locked"]


def test_ubuntu_work_profile_generates_browser_and_ssh_policy():
    profile = read("profiles/ubuntu-work/flake.nix")

    assert 'writeShellScriptBin "work-browser"' in profile
    assert "pkgs.makeDesktopItem" in profile
    assert 'name = "work-browser";' in profile
    assert 'writeTextDir "share/ubuntu-work/sshd_config"' in profile
    assert "PasswordAuthentication no" in profile
    assert "PubkeyAuthentication yes" in profile
    assert "PermitRootLogin no" in profile
    assert "X11Forwarding no" in profile
    assert "AllowUsers erik" in profile


def test_ubuntu_work_guest_profile_has_one_deploy_entrypoint():
    deploy_path = Path("scripts/deploy-ubuntu-work-profile.sh")

    assert deploy_path.exists()
    assert deploy_path.stat().st_mode & 0o111

    deploy = deploy_path.read_text()
    justfile = read("justfile")

    assert "nix-bin nix-setup-systemd" in deploy
    assert "qemu-guest-agent" in deploy
    assert "usermod -aG nix-users" in deploy
    assert "systemctl enable --now nix-daemon.service" in deploy
    assert "systemctl enable --now nix-daemon.socket" not in deploy
    assert "nix-profile-daemon.sh /etc/profile.d/nix.sh" in deploy
    assert "rsync" in deploy
    assert 'build --profile "$HOME/.nix-profile" .#default' in deploy
    assert 'rm -f "$HOME/.config/autostart/brave-browser.desktop"' in deploy
    assert '"$repo_root/config/keyboard/us_qwerty-fr"' in deploy
    assert "/usr/share/X11/xkb/symbols/qwerty-fr" in deploy
    assert '/etc/ssh/sshd_config.d/90-nix-work.conf' in deploy
    assert "/usr/sbin/sshd -t" in deploy
    assert "systemctl reload ssh" in deploy
    assert '"$HOME/.nix-profile/bin/work-browser" --version' in deploy
    assert '"$HOME/.nix-profile/bin/brave" --version' not in deploy
    assert "curl |" not in deploy
    assert "scripts/deploy-ubuntu-work-profile.sh" in justfile


def test_ubuntu_work_warp_connect_is_scoped_to_the_vm():
    justfile = read("justfile")

    assert "ubuntu-work-warp-connect:" in justfile
    assert "erik@192.168.122.74 'warp-cli --accept-tos connect'" in justfile


def test_ubuntu_work_viewer_has_a_direct_just_entrypoint():
    justfile = read("justfile")

    assert "ubuntu-work-define:" in justfile
    assert "virsh --connect qemu:///system define modules/hosts/endeavour/ubuntu-work-domain.xml" in justfile
    assert "ubuntu-work-view:" in justfile
    assert "virt-viewer --connect qemu:///system --reconnect --auto-resize=always --attach ubuntu-work" in justfile


def test_brave_migration_copies_requested_browser_state_and_enables_dark_mode():
    migration_path = Path("scripts/sync-ubuntu-work-brave-settings.sh")

    assert migration_path.exists()
    assert migration_path.stat().st_mode & 0o111

    migration = migration_path.read_text()
    justfile = read("justfile")

    assert 'source_profile="$HOME/.config/BraveSoftware/Brave-Browser/Default"' in migration
    assert '"$source_profile/Bookmarks"' in migration
    assert '"$source_profile/History"' in migration
    assert "PRAGMA quick_check" in migration
    assert '"$HOME/.nix-profile/bin/sqlite3" "$incoming/History"' in migration
    assert "ExtensionInstallForcelist" in migration
    assert "https://clients2.google.com/service/update2/crx" in migration
    assert "curl --fail --location --silent --output /dev/null" in migration
    assert "/etc/brave/policies/managed/90-user-extensions.json" in migration
    assert 'rsync --archive "$incoming/Extensions/" "$profile/Extensions/"' not in migration
    assert 'find "$profile" -maxdepth 1 -name History-journal -delete' in migration
    assert "for browser_dir in Brave-Browser Brave-Browser-Xpra; do" in migration
    assert 'profile="$HOME/.config/BraveSoftware/$browser_dir/Default"' in migration
    assert "bookmark_bar" in migration
    assert "always_show_bookmark_bar_on_ntp" in migration
    assert "enable_window_closing_confirm" in migration
    assert "color_scheme2: 2" in migration
    assert "color-scheme prefer-dark" in migration
    assert "gtk-theme Yaru-dark" in migration
    assert 'jq empty "$incoming/Preferences.new"' in migration
    assert 'jq -e empty "$incoming/Preferences.new"' not in migration
    for private_state in [
        "Cookies",
        "Login Data",
        "Local State",
        "Secure Preferences",
        '"$source_profile/Extensions/"',
        "Local Extension Settings",
        "Sync Extension Settings",
    ]:
        assert private_state not in migration
    assert "sync-ubuntu-work-brave-settings:" in justfile
    assert "scripts/sync-ubuntu-work-brave-settings.sh" in justfile
