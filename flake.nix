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

  outputs = { self, nixpkgs, ... }: {
    nixosConfigurations = {
      laptop = nixpkgs.lib.nixosSystem {
        specialArgs = {inherit inputs;};
        modules = [
          inputs.impermanence.nixosModule
          ({ config, ... }: {
            networking.hostName = "nixos-laptop";
          })

        inputs.disko.nixosModules.default
        (import ./laptop/disk.nix { device = "/dev/sdb"; })

          ./hosts/laptop/hadware-configuration.nix
          ./modules/system/core.nix
          ./modules/gui/core.nix
        ];
      };
    };
  };
}
