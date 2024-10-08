{
  self,
  inputs,
  homeImports,
  ...
}: {
  flake.nixosConfigurations = let
    # shorten paths
    inherit (inputs.nixpkgs.lib) nixosSystem;
    mod = "${self}/system";

    # get the basic config to build on top of
    inherit (import "${self}/system") desktop laptop;

    # get these into the module system
    specialArgs = {inherit inputs self;};
  in {
    aesthetic = nixosSystem {
      inherit specialArgs;
      modules =
        desktop
        ++ laptop
        ++ [
          ./aesthetic
          "${mod}/programs/gamemode.nix"
          # "${mod}/programs/hyprland.nix"
          "${mod}/services/gnome-services.nix"
          "${mod}/services/location.nix"
          # "${mod}/core/lanzaboote.nix"
          {
            home-manager = {
              users.erik.imports =
                homeImports."erik@aesthetic";
              extraSpecialArgs = specialArgs;
            };
          }
          inputs.disko.nixosModules.default
          inputs.impermanence.nixosModules.impermanence
          inputs.agenix.nixosModules.default
        ];
    };
  };
}
