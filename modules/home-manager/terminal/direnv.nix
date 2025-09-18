{config, ...}: {
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true; # Cache .env environment
    silent = true; # Silence direnv messages

    config = {
      # Whitelist configuration
      whitelist = {
        # Allow entire directory hierarchies
        prefix = [
          "${config.home.homeDirectory}/Documents/erik"
          "${config.home.homeDirectory}/Documents/nstech"
        ];
      };
      hide_env_diff = true;
      warn_timeout = "10s"; # Warning timeout
      disable_stdin = true; # Disable stdin during .envrc evaluation
    };
  };
}
