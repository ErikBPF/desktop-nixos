{
  perSystem = {pkgs, ...}: {
    devShells.default = pkgs.mkShell {
      packages = [
        pkgs.statix
        pkgs.just
        pkgs.alejandra
      ];
    };
  };
}
