_: {
  flake.modules.nixos.dev-paths = {pkgs, ...}: let
    languagePaths = [
      "${pkgs.dotnet-sdk_10}/bin"
      "$HOME/go/bin"
      "${pkgs.go}/bin"
      "$HOME/.local/bin"
      "${pkgs.jdk}/bin"
      "${pkgs.gradle}/bin"
      "${pkgs.maven}/bin"
      "${pkgs.nodejs_22}/bin"
      "$HOME/.npm-packages/bin"
    ];
    devToolPaths = [
      "${pkgs.gh}/bin"
      "${pkgs.git}/bin"
      "${pkgs.vim}/bin"
      "${pkgs.alejandra}/bin"
      "${pkgs.nil}/bin"
      "${pkgs.nixd}/bin"
      "${pkgs.nixfmt}/bin"
    ];
    allPaths = languagePaths ++ devToolPaths;
    concatenatedPath = builtins.concatStringsSep ":" allPaths;
  in {
    environment.sessionVariables = {
      PATH = "${concatenatedPath}:$PATH";
      DOTNET_ROOT = "${pkgs.dotnet-sdk_10}";
      GOROOT = "${pkgs.go}";
      JAVA_HOME = "${pkgs.jdk}";
      JDK_HOME = "${pkgs.jdk}";
    };
  };
}
