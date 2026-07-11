_: {
  # General-purpose multiplexer for plain SSH / non-herdr sessions (herdr owns
  # the AI-agent panes). Base16 theming comes from the stylix tmux target,
  # enabled centrally in modules/desktop/stylix.nix so this module stays
  # portable to hosts without stylix (e.g. the orion dev-sandbox microvm).
  # Session save/restore is intentionally omitted: herdr already provides
  # session persistence, so no resurrect/continuum here.
  flake.modules.home.tmux = {pkgs, ...}: {
    programs.tmux = {
      enable = true;
      shell = "${pkgs.fish}/bin/fish";
      keyMode = "vi";
      mouse = true;
      baseIndex = 1;
      escapeTime = 10;
      historyLimit = 50000;
      terminal = "tmux-256color";
      plugins = with pkgs.tmuxPlugins; [
        sensible
        vim-tmux-navigator
        yank
      ];
    };
  };
}
