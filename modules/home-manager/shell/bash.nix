{ ... }:
let
  aliases = import ./aliases.nix { };
in
{

  programs.bash = {
    enable = true;
    shellAliases = aliasses;
    initExtra = ''
      export PS1='\[\e[38;5;76m\]\u\[\e[0m\] in \[\e[38;5;32m\]\w\[\e[0m\] \\$ '
    '';
  };
}