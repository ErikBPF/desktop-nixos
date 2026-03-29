_: {
  flake.modules.nixos.dev-dotnet = {pkgs, ...}: {
    environment.systemPackages = with pkgs; [
      dotnet-sdk_10
      dotnet-runtime_10
      dotnet-aspnetcore_10
      dotnet-ef
      dotnet-outdated
      msbuild
      nuget
      omnisharp-roslyn
      csharp-ls
    ];

    environment.sessionVariables = {
      DOTNET_ROOT = "${pkgs.dotnet-sdk_10}";
      DOTNET_CLI_TELEMETRY_OPTOUT = "1";
      DOTNET_SKIP_FIRST_TIME_EXPERIENCE = "1";
      DOTNET_NOLOGO = "1";
      DOTNET_EnableEventLog = "1";
      DOTNET_UseSharedCompilation = "1";
      DOTNET_EnableDiagnostics = "1";
      DOTNET_EnableTieredCompilation = "1";
      DOTNET_TieredCompilation = "1";
    };
  };
}
