# Receiving end of the off-site restic backup: a dedicated, unprivileged user
# that another host pushes an (already-encrypted) restic repo to over SFTP.
# Contained by design — no root trust between hosts; the authorized key can only
# act as this user, and `restrict` drops pty/forwarding. The pushing host holds
# the matching private key (sops); see restic-tofu-state.nix.
{...}: {
  flake.modules.nixos.restic-offsite-target = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.services.resticOffsiteTarget;
  in {
    options.services.resticOffsiteTarget = {
      enable = lib.mkEnableOption "host as an off-site restic SFTP target";

      authorizedKey = lib.mkOption {
        type = lib.types.str;
        description = "SSH public key allowed to push backups (the pushing host's dedicated key).";
      };

      dir = lib.mkOption {
        type = lib.types.str;
        default = "/var/lib/restic-offsite";
        description = "Backup root; also the dedicated user's home. Put it on a roomy pool.";
      };
    };

    config = lib.mkIf cfg.enable {
      users.groups.restic-offsite = {};
      users.users.restic-offsite = {
        isSystemUser = true;
        group = "restic-offsite";
        home = cfg.dir;
        createHome = true;
        # sftp runs as the sshd subsystem, not via a login shell — nologin keeps
        # the account non-interactive while SFTP still works.
        shell = "${pkgs.shadow}/bin/nologin";
        openssh.authorizedKeys.keys = [
          "restrict ${cfg.authorizedKey}"
        ];
      };
    };
  };
}
