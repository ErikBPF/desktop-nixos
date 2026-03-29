_: {
  flake.modules.home.direnv = {config, ...}: {
    programs.direnv = {
      enable = true;
      nix-direnv.enable = true;
      silent = true;
      enableBashIntegration = true;
      config = {
        global = {
          log_format = "-";
          log_filter = "^$";
          hide_env_diff = true;
        };
        whitelist = {
          prefix = [
            "${config.home.homeDirectory}/Documents/erik"
            "${config.home.homeDirectory}/Documents/nstech"
          ];
        };
        hide_env_diff = true;
        warn_timeout = "10s";
        disable_stdin = true;
      };
    };
  };
}
