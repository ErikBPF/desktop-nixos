{
  pkgs,
  ...
}: let
  # Collect all language-specific paths
  languagePaths = [
    # .NET paths
    "${pkgs.dotnet-sdk_9}/bin"
    
    # Go paths
    "$HOME/go/bin"
    "${pkgs.go}/bin"
    
    # Python paths
    "$HOME/.local/bin"
    
    # Java paths
    "${pkgs.zulu23}/bin"
    "${pkgs.gradle}/bin"
    "${pkgs.maven}/bin"
  ];
  
  # Additional development tool paths
  devToolPaths = [
    "${pkgs.gh}/bin"
    "${pkgs.git}/bin"
    "${pkgs.vim}/bin"
    "${pkgs.alejandra}/bin"
    "${pkgs.nil}/bin"
    "${pkgs.nixd}/bin"
    "${pkgs.nixfmt-rfc-style}/bin"
  ];
  
  # Combine all paths
  allPaths = languagePaths ++ devToolPaths;
  
  # Create PATH string
  concatenatedPath = builtins.concatStringsSep ":" allPaths;
in {
  # Set environment variables including concatenated PATH
  environment.sessionVariables = {
    # Concatenated PATH
    PATH = "${concatenatedPath}:$PATH";
    
    # Language-specific paths
    DOTNET_ROOT = "${pkgs.dotnet-sdk_9}";
    GOROOT = "${pkgs.go}";
    JAVA_HOME = "${pkgs.zulu23}";
    JDK_HOME = "${pkgs.zulu23}";
  };
}
