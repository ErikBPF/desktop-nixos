{inputs, ...}: {
  flake.modules.home.codex = {
    config,
    lib,
    pkgs,
    ...
  }: {
    imports = [inputs.codex-flake.homeManagerModules.withPackage];

    programs.codex-profile = {
      enable = true;
      package.enable = true;
      rtk.enable = true;
      style.enable = true;
    };

    home.activation.installCodexPonytail = lib.hm.dag.entryAfter ["installPackages"] ''
      export PATH=${lib.makeBinPath [pkgs.git]}:$PATH
      if ! ${lib.getExe config.programs.codex.package} plugin list --json |
        ${lib.getExe pkgs.jq} -e 'any(.installed[]; .pluginId == "ponytail@ponytail")' >/dev/null; then
        run ${lib.getExe config.programs.codex.package} plugin marketplace add ${inputs.ponytail}
        run ${lib.getExe config.programs.codex.package} plugin add ponytail@ponytail
      fi
    '';
  };
}
