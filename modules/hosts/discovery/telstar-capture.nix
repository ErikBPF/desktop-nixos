{
  config,
  inputs,
  ...
}: {
  # Persistent retry that creates the Oracle Always-Free A1 `telstar` instance
  # the moment free-tier capacity frees ("Out of host capacity" is intermittent
  # in sa-saopaulo-1). Runs on discovery (always-on). Declarative replacement for
  # the earlier hand-placed `systemd-run --user` job.
  #
  # Reuses the retry script from the pinned homelab-iac input — SSOT for the
  # oracle stack and the encrypted OCI creds, which discovery decrypts at
  # runtime. A system service with User=erik survives reboots without linger. See
  # homelab-iac/oracle/telstar-capture-status.md.
  flake.modules.nixos.discovery-telstar-capture = {
    lib,
    pkgs,
    ...
  }: let
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
    systemd.services.telstar-capture = lib.mkIf (config.fleet.hosts.telstar.ip == null) {
      description = "Retry Oracle A1 telstar create until free-tier capacity frees";
      wantedBy = ["multi-user.target"];
      after = ["network-online.target"];
      wants = ["network-online.target"];
      # This long retry loop is already running the pinned IaC revision. A
      # switch must not restart it while the local S3/proxy stack is cycling.
      restartIfChanged = false;
      stopIfChanged = false;
      path = with pkgs; [openssh sops coreutils gnugrep gnutar bash];
      environment = {
        OCI_SSH_PUBKEY_FILE = "${telstarPubkey}";
        TENV_AUTO_INSTALL = "true";
        TF_PLUGIN_CACHE_DIR = "/var/lib/telstar-capture/plugin-cache";
      };
      # If the loop hits a real (non-capacity) error it exits non-zero; bound the
      # restart so a genuine break doesn't hammer every 5 min forever.
      startLimitIntervalSec = 3600;
      startLimitBurst = 5;
      serviceConfig = {
        Type = "simple";
        User = user;
        Group = "users";
        StateDirectory = "telstar-capture";
        StateDirectoryMode = "0700";
        WorkingDirectory = "/var/lib/telstar-capture";
        Restart = "on-failure";
        RestartPreventExitStatus = [75];
        RestartSec = "300";
      };
      # Copy the reviewed source closure into a writable runtime directory, then
      # run its retry script (own PATH/sops/tenv/creds handling inside).
      script = ''
        set -euo pipefail
        export PATH="/run/current-system/sw/bin:${home}/.nix-profile/bin:$PATH"
        rm -rf "$STATE_DIRECTORY/source"
        cp -R --no-preserve=mode ${inputs.homelab-iac} "$STATE_DIRECTORY/source"
        mkdir -p "$TF_PLUGIN_CACHE_DIR"
        export REPO="$STATE_DIRECTORY/source"
        cd "$STATE_DIRECTORY/source"
        exec ${pkgs.bash}/bin/bash oracle/bin/telstar-get-retry.sh
      '';
    };
  };
}
