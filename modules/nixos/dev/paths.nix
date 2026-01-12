{
  config,
  pkgs,
  lib,
  ...
}: let
  # Collect all language-specific paths
  languagePaths = [
    # .NET paths
    "${pkgs.dotnet-sdk_10}/bin"

    # Go paths
    "$HOME/go/bin"
    "${pkgs.go}/bin"

    # Python paths
    "$HOME/.local/bin"

    # Java paths
    "${pkgs.jdk}/bin"
    "${pkgs.gradle}/bin"
    "${pkgs.maven}/bin"

    # Node.js paths
    "${pkgs.nodejs_22}/bin"
    "$HOME/.npm-packages/bin"
  ];

  # Additional development tool paths
  devToolPaths = [
    "${pkgs.gh}/bin"
    "${pkgs.git}/bin"
    "${pkgs.vim}/bin"
    "${pkgs.alejandra}/bin"
    "${pkgs.nil}/bin"
    "${pkgs.nixd}/bin"
    "${pkgs.nixfmt}/bin"
  ];

  # Combine all paths
  allPaths = languagePaths ++ devToolPaths;

  # Create PATH string
  concatenatedPath = builtins.concatStringsSep ":" allPaths;
in {
  config = lib.mkIf config.modules.dev.enable {
    # Set environment variables including concatenated PATH
    environment.sessionVariables = {
      # Concatenated PATH
      PATH = "${concatenatedPath}:$PATH";

      # Language-specific paths
      DOTNET_ROOT = "${pkgs.dotnet-sdk_10}";
      GOROOT = "${pkgs.go}";
      JAVA_HOME = "${pkgs.jdk}";
      JDK_HOME = "${pkgs.jdk}";
    };
  };
}
