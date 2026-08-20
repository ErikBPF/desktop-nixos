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
      agents.extraText = builtins.readFile ./agent-policy.md;
    };

    home.file.".agents/skills/codehero".source = ./codex-skills/codehero;
    home.file.".agents/skills/grill".source = ./codex-skills/grill;
    home.file.".agents/skills/ip".source = ./codex-skills/ip;
    home.file.".agents/skills/map".source = ./codex-skills/map;
    home.file.".agents/skills/party".source = ./codex-skills/party;
    home.file.".agents/skills/pl".source = ./codex-skills/pl;
    home.file.".agents/skills/rv".source = ./codex-skills/rv;

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
