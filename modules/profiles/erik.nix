{config, ...}: let
  m = config.flake.modules;
in {
  # Shared non-GUI tooling for Erik's workstations. Host profiles add GUI or
  # compute-specific modules. SSH private keys and their sops backing stay in
  # profile-base; Vault must never render ~/.ssh/id_*.
  flake.modules.nixos.profile-erik = {pkgs, ...}: {
    imports = [
      m.nixos.dev-python
      m.nixos.dev-javascript
      m.nixos.dev-go
      m.nixos.dev-java
      m.nixos.dev-dotnet
      m.nixos.dev-paths
      m.nixos.dev-nix-ld
      m.nixos.opencode-client
      m.nixos.hermes-client
    ];

    environment.systemPackages = with pkgs; [
      nvtopPackages.full
      zellij
    ];
  };

  flake.modules.home.profile-erik = {...}: {
    imports = [
      m.home.nvim
      m.home.codex
      m.home.opencode
      m.home.claude-code
      m.home.goose
      m.home.hermes-agent
      m.home.pi
      m.home.herdr
      m.home.tuicr
    ];
  };
}
