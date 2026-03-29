{...}: {
  flake.modules.home.laptop-ssh = {...}: {
    # Machine-specific SSH Host entries for laptop
    # Shared SSH client defaults are in modules/ssh.nix
  };
}
