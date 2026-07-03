{config, ...}: {
  flake.modules.home.git = _: {
    programs.git = {
      enable = true;
      settings = {
        user = {
          name = config.fullName;
          inherit (config) email;
        };
        credential.helper = "store";
      };
    };
    # Syntax-highlighted, navigable diffs (also used by lazygit).
    programs.delta = {
      enable = true;
      enableGitIntegration = true;
      options = {
        navigate = true;
        line-numbers = true;
        side-by-side = true;
      };
    };
  };
}
