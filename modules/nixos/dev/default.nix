{
  lib,
  ...
}: {
  imports = [
    ./paths.nix
    ./dotnet.nix
    ./go.nix
    ./python.nix
    ./java.nix
    ./javascript.nix
  ];

  options.modules.dev.enable = lib.mkEnableOption "development tools and environments";
}
