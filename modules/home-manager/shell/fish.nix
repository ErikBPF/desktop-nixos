{...}: let
  aliases = import ./aliases.nix {};
in {
  programs.fish = {
    enable = true;
    shellAliases = aliases;
  };
}
