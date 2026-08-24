{inputs, ...}: {
  flake.modules.home.deepseek-harness = {pkgs, ...}: let
    system = pkgs.stdenv.hostPlatform.system;
  in {
    home.packages = [inputs.deepseek-harness-flake.packages.${system}.default];
    home.sessionVariables.DSH_TELEMETRY_DISABLED = "1";
    programs.zsh.shellAliases.dp = "env DSH_PERMISSION_MODE=danger-full-access DSH_TELEMETRY_DISABLED=1 dsh web";
  };
}
