# Edit trueconfiguration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{
  self,
  inputs,
  lib,
  ...
}: let
  inherit
    (self.inputs)
    disko
    ;

 nixosSystem = args:
    (lib.makeOverridable lib.nixosSystem)
    (lib.recursiveUpdate args {
      modules =
        args.modules
        ++ [
          {
            config.nixpkgs.pkgs = lib.mkDefault args.pkgs;
            config.nixpkgs.localSystem = lib.mkDefault args.pkgs.stdenv.hostPlatform;
          }
        ];
    });

  # hosts = lib.rakeLeaves ./hosts;
  # modules = lib.rakeLeaves ./modules;

  defaultModules = [
    # make flake inputs accessible in NixOS
    {
      # module.args.self = self;
      # module.args.inputs = inputs;
    }
    # load common modules
    ({...}: {
      imports = [
        # impermanence.nixosModules.impermanence
        disko.nixosModules.disko

        # modules.i18n
        # modules.minimal-docs
        # modules.nix
        # modules.openssh
        # modules.pgweb
        # modules.server
        # modules.tailscale
      ];
    })
  ];

{

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  # FIXME: change it to version from your current, fresh and auto-generated after first installation `configuration.nix` config file
  system.stateVersion = "23.11"; # Did you read the comment?

}
