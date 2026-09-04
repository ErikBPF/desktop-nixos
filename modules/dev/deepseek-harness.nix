{inputs, ...}: {
  flake.modules.home.deepseek-harness = {
    lib,
    pkgs,
    ...
  }: let
    system = pkgs.stdenv.hostPlatform.system;
    harness = inputs.deepseek-harness-flake.packages.${system}.default;
    secretSpec = pkgs.writeText "deepseek-harness-secretspec.toml" ''
      [project]
      name = "deepseek-harness"
      revision = "1.0"

      [profiles.default]
      LITELLM_HOMELAB_API_KEY = { description = "Authorize the homelab LiteLLM route", required = true }
    '';
    tui = pkgs.writeShellApplication {
      name = "dsh-tui";
      text = ''
        exec ${pkgs.secretspec}/bin/secretspec run \
          --file ${secretSpec} \
          --profile default \
          --provider keyring \
          --reason endeavour-deepseek-harness-tui \
          -- ${harness}/bin/dsh-tui "$@"
      '';
    };
  in {
    home.packages = [harness pkgs.secretspec (lib.hiPrio tui)];
    home.sessionVariables.DSH_TELEMETRY_DISABLED = "1";
    xdg.configFile."secretspec/config.toml".text = ''
      [defaults]
      provider = "keyring"

      [defaults.providers]
      keyring = "keyring://"
    '';
    programs.zsh.shellAliases.dp = "env DSH_PERMISSION_MODE=danger-full-access DSH_TELEMETRY_DISABLED=1 dsh web";
  };
}
