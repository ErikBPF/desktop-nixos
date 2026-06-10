{
  config,
  inputs,
  ...
}: let
  m = config.flake.modules;
in {
  # Shared home-manager wiring for every host: global pkgs, sops, the base
  # home profile, xdg defaults and stateVersion. Host modules add their
  # extras (profile-desktop, <host>-ssh, colorScheme, monitor layout) via
  # home-manager.users.<user> — definitions merge across modules.
  flake.modules.nixos.home-manager-base = _: {
    home-manager = {
      useGlobalPkgs = true;
      backupFileExtension = "backup";
      users.${config.username} = {
        imports = [
          inputs.sops-nix.homeManagerModules.sops
          m.home.profile-base
        ];
        home = {
          inherit (config) username;
          homeDirectory = "/home/${config.username}";
          stateVersion = "25.11";
        };
        xdg = {
          enable = true;
          userDirs = {
            enable = true;
            createDirectories = true;
            setSessionVariables = true;
          };
        };
        programs.home-manager.enable = true;
      };
    };
  };
}
