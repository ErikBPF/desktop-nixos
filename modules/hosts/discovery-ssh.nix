{...}: {
  flake.modules.home.discovery-ssh = {...}: {
    # Machine-specific SSH Host entries for discovery
    # Shared SSH client defaults are in modules/ssh.nix
  };
}
