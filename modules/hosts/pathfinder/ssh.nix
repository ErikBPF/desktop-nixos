{...}: {
  flake.modules.home.pathfinder-ssh = {...}: {
    # Machine-specific SSH Host entries for pathfinder
    # Shared SSH client defaults are in modules/ssh.nix
  };
}
