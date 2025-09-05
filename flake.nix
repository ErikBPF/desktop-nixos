{

inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.05";
    nixpkgs-master.url = "github:NixOS/nixpkgs/master";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixpkgs-unstable";

    # Note: Currently pinned to 25.05
    home-manager.url = "github:nix-community/home-manager/release-25.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    nixos-hardware.url = "github:NixOS/nixos-hardware/master";

    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";

    hyprland.url = "github:hyprwm/Hyprland";
    nix-colors.url = "github:misterio77/nix-colors";

  };

  outputs =
    {
     self,
      nixpkgs,
      disko,
      home-manager,
      hyprland,
      nix-colors,
      ...
    }@ inputs: let
    inherit (self) outputs;
    systems = [
      "x86_64-linux"
      "aarch64-darwin"
    ];
    forAllSystems = nixpkgs.lib.genAttrs systems;
  in {
    formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.alejandra);

    overlays = import ./overlays {inherit inputs;};
    nixosModules = {
      default = {
        config,
        lib,
        pkgs,
        ...
      }: {
        imports = [
          (import ./modules/nixos/default.nix inputs)
        ];
      };
    };
    homeManagerModules = import {
      default = {
        config,
        lib,
        pkgs,
        osConfig ? {},
        ...
      }: {
        imports = [
          nix-colors.homeManagerModules.default
          (import ./modules/home-manager/default.nix inputs)
        ];
      };
    };
    nixosConfigurations = {
      workstation = nixpkgs.lib.nixosSystem {
        specialArgs = {inherit inputs outputs;};
        system = "x86_64-linux";
        modules = [./hosts/workstation];
      };

    };
  };
}