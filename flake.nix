{
  description = "Erik's NixOS Config";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    impermanence.url = "github:nix-community/impermanence";

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, impermanence, disko }: {
    nixosConfigurations = {
      laptop = nixpkgs.lib.nixosSystem {
        modules = [
          impermanence.nixosModule
          ({ config, ... }: {
            networking.hostName = "nixos-laptop";
          })

        disko.nixosModules.default
        (import ./laptop/disk.nix { device = "/dev/sdb"; })

          ./hosts/laptop/hadware-configuration.nix
          ./modules/system/core.nix
          ./modules/gui/core.nix
        ];
      };
    };
  };
}
