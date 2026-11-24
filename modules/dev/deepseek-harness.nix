{inputs, ...}: {
  flake.modules.home.deepseek-harness = {
    lib,
    pkgs,
    ...
  }: let
    system = pkgs.stdenv.hostPlatform.system;
    harness = inputs.deepseek-harness-flake.packages.${system}.default;
    tui = pkgs.writeShellApplication {
      name = "dsh-tui";
      text = ''
        exec ${harness}/bin/dsh-tui "$@"
      '';
    };
  in {
    home.packages = [harness pkgs.secretspec (lib.hiPrio tui)];
    home.sessionVariables.DSH_TELEMETRY_DISABLED = "1";
    programs.zsh.shellAliases.dp = "env DSH_PERMISSION_MODE=danger-full-access DSH_TELEMETRY_DISABLED=1 dsh web";
  };
}
