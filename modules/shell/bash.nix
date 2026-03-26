{...}: {
  flake.modules.home.bash = {...}: let
    aliases = import ./_aliases.nix {};
  in {
    programs.bash = {
      enable = true;
      shellAliases = aliases;
      initExtra = ''
        export PS1='\[\e[38;5;76m\]\u\[\e[0m\] in \[\e[38;5;32m\]\w\[\e[0m\] \\$ '

        # devenv shell integration
        if [ -n "$DEVENV_SHELL" ]; then
          eval "$(devenv print-dev-env --shell bash)"
        fi

        # direnv integration for bash
        if command -v direnv >/dev/null 2>&1; then
          eval "$(direnv hook bash)"
        fi
      '';
    };
  };
}
