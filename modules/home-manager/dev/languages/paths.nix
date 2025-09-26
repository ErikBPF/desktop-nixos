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
    "${pkgs.nvim}/bin"
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
  # Set the concatenated PATH
  home.sessionVariables = {
    PATH = "${concatenatedPath}:$PATH";
  };
  
  # Individual path exports for reference
  home.sessionVariablesExtra = ''
    # Language-specific paths
    export DOTNET_ROOT="${pkgs.dotnet-sdk_9}"
    export GOROOT="${pkgs.go}"
    export JAVA_HOME="${pkgs.zulu23}"
    export JDK_HOME="${pkgs.zulu23}"
    
    # Development tool paths
    export EDITOR="nvim"
    export VISUAL="nvim"
    
    # Nix development paths
    export NIX_PATH="nixpkgs=${pkgs.path}"
  '';
}
