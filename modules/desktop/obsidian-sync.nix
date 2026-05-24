{config, ...}: let
  inherit (config) username;
  vault = "/home/${username}/Documents/erik/obsidian/vault";
in {
  flake.modules.home.obsidian-sync = {pkgs, ...}: let
    syncScript = pkgs.writeShellApplication {
      name = "obsidian-vault-sync";
      runtimeInputs = [pkgs.git pkgs.openssh pkgs.coreutils];
      text = ''
        set -euo pipefail
        cd "${vault}"

        # Strip nix-symlink .backup noise before commit
        rm -f .obsidian/*.backup 2>/dev/null || true

        if [ ! -d .git ]; then
          echo "vault not a git repo — run manual init first" >&2
          exit 1
        fi

        if ! git remote get-url origin >/dev/null 2>&1; then
          echo "no origin remote — run manual init first" >&2
          exit 1
        fi

        if [ -n "$(git status --porcelain)" ]; then
          git add -A
          git commit -m "vault: auto $(date -Iseconds)" || true
        fi

        git fetch origin
        if ! git rebase --autostash origin/main; then
          echo "rebase conflict — manual intervention required" >&2
          git rebase --abort || true
          exit 2
        fi

        git push origin main
      '';
    };
  in {
    home.packages = [syncScript];

    systemd.user.services.obsidian-vault-sync = {
      Unit = {
        Description = "Obsidian vault git sync";
        After = ["network-online.target"];
      };
      Service = {
        Type = "oneshot";
        ExecStart = "${syncScript}/bin/obsidian-vault-sync";
        Nice = 10;
      };
    };

    systemd.user.timers.obsidian-vault-sync = {
      Unit.Description = "Periodic Obsidian vault sync";
      Timer = {
        OnBootSec = "5m";
        OnUnitActiveSec = "30m";
        Persistent = true;
        RandomizedDelaySec = "60s";
      };
      Install.WantedBy = ["timers.target"];
    };
  };
}
