{
  config,
  lib,
  ...
}: let
  inherit (config) username;

  # path:upstream-remote:upstream-branch:fork-remote
  # Fast-forward-only mirror sync: fetch upstream branch, push it to the fork.
  # Diverged forks (non-FF) are reported and skipped, never force-pushed.
  # NOTE: llama-cpp-private master is a private integration line (661 commits
  # ahead) — rebased manually, never auto-synced.
  forks = [
    "/home/${username}/Documents/erik/LMCache:upstream:dev:origin"
    "/home/${username}/Documents/erik/sail:origin:main:fork"
    "/home/${username}/Documents/erik/FreeToken:upstream:main:erikbpf"
    "/home/${username}/Documents/erik/airflow:upstream:main:origin"
    "/home/${username}/Documents/erik/datafusion-comet:origin:main:fork"
  ];
in {
  flake.modules.home.github-fork-sync = {pkgs, ...}: let
    syncScript = pkgs.writeShellApplication {
      name = "github-fork-sync";
      runtimeInputs = [pkgs.git pkgs.coreutils];
      text = ''
        set -uo pipefail

        status=0
        for entry in ${lib.concatStringsSep " " (map lib.escapeShellArg forks)}; do
          path="''${entry%%:*}"
          rest="''${entry#*:}"
          upstream_remote="''${rest%%:*}"
          rest="''${rest#*:}"
          branch="''${rest%%:*}"
          fork_remote="''${rest##*:}"

          if [ ! -d "$path/.git" ]; then
            echo "fork-sync: skip (missing repo) $path" >&2
            continue
          fi

          if git -C "$path" fetch "$upstream_remote" "+$branch:refs/remotes/$upstream_remote/$branch" 2>/dev/null \
            && git -C "$path" push "$fork_remote" "refs/remotes/$upstream_remote/$branch:refs/heads/$branch" 2>/dev/null; then
            echo "fork-sync: synced $path ($branch)"
          else
            echo "fork-sync: SKIPPED (diverged or unreachable) $path ($branch)" >&2
            status=1
          fi
        done
        exit $status
      '';
    };
  in {
    home.packages = [syncScript];

    # Manual only until target-scoped nonhuman credentials are provisioned.
  };
}
