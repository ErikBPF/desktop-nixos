_: {
  # Persistent retry that creates the Oracle Always-Free A1 `telstar` instance
  # the moment free-tier capacity frees ("Out of host capacity" is intermittent
  # in sa-saopaulo-1). Runs on discovery (always-on). Declarative replacement for
  # the earlier hand-placed `systemd-run --user` job.
  #
  # Reuses the retry script from the homelab-iac clone — SSOT for the oracle
  # stack and the OCI creds in `.env.sops`, which discovery (a sops recipient)
  # decrypts at runtime, the same runtime-git pattern as servarr-pull. A system
  # service with User=erik survives reboots without linger. See
  # homelab-iac/oracle/telstar-capture-status.md.
  flake.modules.nixos.discovery-telstar-capture = {pkgs, ...}: let
    # Fleet username (meta.nix `username`, readOnly "erik"); referenced directly
    # since that option is flake-level, not a nixos config attr in this context.
    user = "erik";
    home = "/home/${user}";
    # Public SSH key injected into the telstar instance (a pubkey is not secret)
    # so the deploy host reaches it for `just deploy-telstar`.
    telstarPubkey = pkgs.writeText "telstar-ssh-key.pub" ''
      ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMxdE+uAvR4Nm2XwZNjTf2Ae8PlrRtnZUI6BBrbGl78u erikbogado@gmail.com
    '';
  in {
    systemd.services.telstar-capture = {
      description = "Retry Oracle A1 telstar create until free-tier capacity frees";
      wantedBy = ["multi-user.target"];
      after = ["network-online.target"];
      wants = ["network-online.target"];
      path = with pkgs; [git openssh sops coreutils gnugrep gnutar bash];
      environment = {
        OCI_SSH_PUBKEY_FILE = "${telstarPubkey}";
        TENV_AUTO_INSTALL = "true";
      };
      # If the loop hits a real (non-capacity) error it exits non-zero; bound the
      # restart so a genuine break doesn't hammer every 5 min forever.
      startLimitIntervalSec = 3600;
      startLimitBurst = 5;
      serviceConfig = {
        Type = "simple";
        User = user;
        Group = "users";
        WorkingDirectory = "${home}/homelab-iac";
        Restart = "on-failure";
        RestartSec = "300";
      };
      # Refresh the clone (latest oracle configs + .env.sops), then run the SSOT
      # retry script (own PATH/sops/tenv/creds handling inside).
      script = ''
        set -uo pipefail
        export PATH="/run/current-system/sw/bin:${home}/.nix-profile/bin:$PATH"
        cd "${home}/homelab-iac"
        ${pkgs.git}/bin/git pull --ff-only 2>/dev/null || true
        exec ${pkgs.bash}/bin/bash oracle/bin/telstar-get-retry.sh
      '';
    };
  };
}
