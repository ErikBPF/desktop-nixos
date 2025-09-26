{
  pkgs,
  ...
}: {
  # .NET Core packages
  home.packages = with pkgs; [
    # .NET SDK and Runtime
    dotnet-sdk_9
    dotnet-runtime_9
    dotnet-aspnetcore_9
    
    # Additional .NET tools
    dotnet-ef # Entity Framework Core tools
    dotnet-outdated # Check for outdated NuGet packages
    dotnet-script # Run C# scripts
    dotnet-trace # Performance tracing
    dotnet-counters # Performance counters
    dotnet-dump # Memory dump analysis
    dotnet-gcdump # GC heap analysis
    dotnet-sos # SOS debugging extension
    
    # Build tools
    msbuild # Microsoft Build Engine
    nuget # .NET package manager
    
    # Development tools
    omnisharp-roslyn # C# language server
    csharp-ls # Alternative C# language server
  ];

  # Environment variables for .NET
  home.sessionVariables = {
    # .NET Core settings
    DOTNET_ROOT = "${pkgs.dotnet-sdk_9}";
    DOTNET_CLI_TELEMETRY_OPTOUT = "1";
    DOTNET_SKIP_FIRST_TIME_EXPERIENCE = "1";
    DOTNET_NOLOGO = "1";
    
    # Performance optimizations
    DOTNET_EnableEventLog = "1";
    DOTNET_UseSharedCompilation = "1";
    DOTNET_EnableDiagnostics = "1";
    DOTNET_EnableTieredCompilation = "1";
    DOTNET_TieredCompilation = "1";
    
    # Path configuration
    PATH = "$PATH:${pkgs.dotnet-sdk_9}/bin";
  };

}
