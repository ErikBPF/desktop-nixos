{ ... }:
let
  aliases = import ./aliases.nix { };
in
{

  programs.bash = {
    enable = true;
    completion.enable = true; # Required for home setting
    shellAliases = aliases;
    initExtra = ''
      export PS1='\[\e[38;5;76m\]\u\[\e[0m\] in \[\e[38;5;32m\]\w\[\e[0m\] \\$ '
    '';
  };
}