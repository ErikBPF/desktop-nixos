_: {
  flake.modules.nixos.kepler-nas = {pkgs, ...}: {
    # --- NFS exports ---
    # /fast and /bulk exported to the LAN (192.168.10.0/24) and Tailscale (100.64.0.0/10).
    # ro: bulk is read-only for clients by default — write access goes through Samba.
    # rw: fast pool is read-write for direct access (models, scratch).
    services.nfs.server = {
      enable = true;
      # Pin auxiliary RPC ports so they can be firewalled/ACL'd deterministically.
      # Without these, mountd/statd/lockd use random ephemeral ports on each boot.
      mountdPort = 4002;
      statdPort = 4000;
      lockdPort = 4001;
      exports = ''
        /fast  192.168.10.0/24(rw,sync,no_subtree_check,no_root_squash) 100.64.0.0/10(rw,sync,no_subtree_check,no_root_squash)
        /bulk  192.168.10.0/24(ro,sync,no_subtree_check,root_squash) 100.64.0.0/10(ro,sync,no_subtree_check,root_squash)
        /fast/k8s  10.250.0.0/24(rw,sync,no_subtree_check,no_root_squash)
        /bulk/k8s  10.250.0.0/24(rw,sync,no_subtree_check,no_root_squash)
      '';
    };

    # csi-driver-nfs PV roots: dedicated subdirs so k3s PVs don't mingle with the
    # model cache (/fast) or media (/bulk). Exported rw to the cluster subnet only
    # (the nodes mount kepler at its br-k3s gateway IP 10.250.0.1). no_root_squash:
    # the CSI node plugin runs as root and chowns each PV dir. nfs-fast → SSD pool,
    # nfs-slow → HDD pool (RFC homelab-gitops §4).
    systemd.tmpfiles.rules = [
      "d /fast/k8s 0755 root root -"
      "d /bulk/k8s 0755 root root -"
    ];

    # --- Samba ---
    # Provides read-write access to bulk storage for Windows/macOS clients
    # and for any client that prefers SMB over NFS.
    services.samba = {
      enable = true;
      openFirewall = false; # managed in networking.nix
      # Disable nmbd (NetBIOS name daemon) — crashes on Samba 4.22 during
      # master browser elections (strlcpy_chk buffer overflow in nmbd).
      # Modern SMB clients use DNS + port 445 directly; NetBIOS not needed.
      nmbd.enable = false;
      settings = {
        global = {
          "workgroup" = "WORKGROUP";
          "server string" = "Kepler NAS";
          "server role" = "standalone server";
          "log level" = "1";
          "max log size" = "50";
          # Security: only LAN + Tailscale, no guest access
          "hosts allow" = "192.168.10.0/24 100.64.0.0/10 127.0.0.1";
          "hosts deny" = "ALL";
          "guest ok" = "no";
          "map to guest" = "Never";
        };
        fast = {
          "path" = "/fast";
          "browseable" = "yes";
          "read only" = "no";
          "valid users" = "erik";
          "create mask" = "0664";
          "directory mask" = "0775";
          "comment" = "Fast SSD pool";
        };
        bulk = {
          "path" = "/bulk";
          "browseable" = "yes";
          "read only" = "no";
          "valid users" = "erik";
          "create mask" = "0664";
          "directory mask" = "0775";
          "comment" = "Bulk HDD pool";
        };
      };
    };

    # Samba user password (separate from system password — must be set after first boot):
    # sudo smbpasswd -a erik

    environment.systemPackages = [pkgs.samba];
  };
}
