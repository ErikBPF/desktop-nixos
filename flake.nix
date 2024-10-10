{
    description = "erik NixOS";

    inputs = {
	    nixpkgs.url = "github:NixOS/nixpkgs/nixos-23.11";
        nixpkgs-unstable.url = "nixpkgs/nixos-unstable";
        home-manager.url = "github:nix-community/home-manager/release-23.11";
        home-manager.inputs.nixpkgs.follows = "nixpkgs";

        firefox-addons = {
            url = "gitlab:rycee/nur-expressions?dir=pkgs/firefox-addons";
            inputs.nixpkgs.follows = "nixpkgs";
        };

        lanzaboote = {
            url = "github:nix-community/lanzaboote/v0.3.0";

            inputs.nixpkgs.follows = "nixpkgs";
        };
        
        disko = {
            url = "github:nix-community/disko";
            inputs.nixpkgs.follows = "nixpkgs";
        };
    };

    outputs = { self, nixpkgs, nixpkgs-unstable, home-manager, lanzaboote, disko, ... }@inputs:
	let 
	    lib = nixpkgs.lib;
	    system = "x86_64-linux";
	    pkgs = nixpkgs.legacyPackages.${system};
        pkgs-unstable = nixpkgs-unstable.legacyPackages.${system};
	in
    {
		nixosConfigurations.laptop = lib.nixosSystem {
                inherit system;
				modules = [
                    ./system/configuration.nix 
                    lanzaboote.nixosModules.lanzaboote 
                    disko.nixosModules.default
				];
                specialArgs = {
                    inherit pkgs-unstable;
                };
        };

		homeConfigurations = {
			erik = home-manager.lib.homeManagerConfiguration {
				inherit pkgs;
				modules = [ ./home ];
                extraSpecialArgs = {
                    inherit pkgs-unstable;
                    inherit inputs;
                };
			};
		};
    };
}
