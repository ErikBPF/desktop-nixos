{inputs, ...}: {
  # herdr — terminal multiplexer that runs several AI coding agents side by
  # side in real panes, with per-agent state (blocked/working/done/idle),
  # session persistence, and a background server you can detach/reattach.
  #
  # herdr does NOT own any agent's auth. claude-code, codex and opencode each
  # carry their own subscription/OAuth in their own config dir (~/.claude,
  # ~/.codex, ~/.config/opencode) and are already logged in on this host — so
  # "configuring the subscriptions on it" just means giving herdr a launcher
  # for each; the CLI it spawns picks up its existing credentials.
  #
  # The local `hermes` CLI (modules/dev/hermes-agent.nix) is likewise just
  # another launcher here; herdr recognises "Hermes Agent" natively for
  # session restore.
  flake.modules.home.herdr = {pkgs, ...}: let
    system = pkgs.stdenv.hostPlatform.system;
    tomlFormat = pkgs.formats.toml {};
  in {
    home.packages = [inputs.herdr.packages.${system}.default];

    # Declarative, read-only config. herdr re-reads it on
    # `herdr server reload-config`; onboarding is disabled so it never tries
    # to write back to this store-symlinked file on first run.
    xdg.configFile."herdr/config.toml".source = tomlFormat.generate "herdr-config.toml" {
      onboarding = false;

      # Nix owns the binary — herdr can't self-update, so don't let it phone
      # home checking for versions/manifests on every launch.
      update = {
        channel = "stable";
        version_check = false;
        manifest_check = false;
      };

      terminal = {
        default_shell = "zsh";
        shell_mode = "auto";
        new_cwd = "follow";
      };

      # Reattach with agents back in place after a detach/restart.
      session.resume_agents_on_restore = true;

      theme = {
        name = "catppuccin";
        auto_switch = false;
      };

      ui = {
        sidebar_width = 32;
        mouse_capture = true;
        confirm_close = true;
        agent_panel_sort = "priority";
        # Surface "agent is blocked / needs input" as an in-herdr toast.
        toast.delivery = "herdr";
        # No bundled sound assets in the Nix package — keep it silent rather
        # than log a missing-file error per event.
        sound.enabled = false;
      };

      # One launcher per agent. `type = "pane"` spawns the CLI in a fresh
      # pane; herdr's process-name + output heuristics then track its state.
      keys.command = [
        {
          key = "prefix+alt+c";
          type = "pane";
          command = "claude";
          description = "launch Claude Code";
        }
        {
          key = "prefix+alt+x";
          type = "pane";
          command = "codex";
          description = "launch Codex";
        }
        {
          key = "prefix+alt+o";
          type = "pane";
          command = "opencode";
          description = "launch opencode";
        }
        {
          key = "prefix+alt+h";
          type = "pane";
          command = "hermes";
          description = "launch Hermes Agent (local CLI → Discovery API)";
        }
      ];
    };
  };
}
