{
  config,
  lib,
  pkgs,
  ...
}: let
  omoPlugin = "oh-my-openagent@5.0.0-beta.43";
  agents = [
    "build"
    "plan"
    "sisyphus"
    "hephaestus"
    "sisyphus-junior"
    "OpenCode-Builder"
    "prometheus"
    "metis"
    "momus"
    "oracle"
    "librarian"
    "explore"
    "multimodal-looker"
    "atlas"
  ];
  categories = [
    "visual-engineering"
    "ultrabrain"
    "deep"
    "artistry"
    "quick"
    "unspecified-low"
    "unspecified-high"
    "writing"
  ];
  profiles = {
    home = {
      provider = "litellm";
      omo = false;
    };
    work = {
      provider = "work";
      omo = false;
    };
    home-omo = {
      provider = "litellm";
      omo = true;
    };
    work-omo = {
      provider = "work";
      omo = true;
    };
  };
  files = name: profile: let
    model = "${profile.provider}/glm-5.3-flash";
    prefix = "opencode/profiles/${name}/";
  in
    {
      "${prefix}opencode.json".text = builtins.toJSON ({
          inherit model;
          small_model = model;
          # v1.18.29's legacy provider path still needs this allowlist. The late
          # profile directory wins over repository provider/model overrides.
          enabled_providers = [profile.provider];
        }
        // (
          if profile.omo
          then {plugin = [omoPlugin];}
          else {default_agent = "build";}
        ));
    }
    // lib.optionalAttrs profile.omo {
      "${prefix}tui.json".text = builtins.toJSON {plugin = [omoPlugin];};
    };
  launcher = name: profile: let
    homeLane = profile.provider == "litellm";
    keyFile =
      if homeLane
      then "litellm_key"
      else "work_key";
    keyVariable =
      if homeLane
      then "OPENCODE_LITELLM_KEY"
      else "OPENCODE_WORK_KEY";
  in
    pkgs.writeShellScriptBin "opencode-${name}" ''
      set -eu
      unset OPENCODE_CONFIG OPENCODE_CONFIG_CONTENT OMO_PROFILE
      ${lib.optionalString profile.omo "export OMO_PROFILE=${lib.escapeShellArg name}"}
      export OPENCODE_CONFIG_DIR=${lib.escapeShellArg "${config.xdg.configHome}/opencode/profiles/${name}"}
      if [ -r /run/secrets/opencode/${keyFile} ]; then
        export ${keyVariable}="$(</run/secrets/opencode/${keyFile})"
      fi
      exec ${config.programs.opencode.package}/bin/opencode "$@"
    '';
in {
  xdg.configFile = lib.foldlAttrs (result: name: profile: result // files name profile) {} profiles;
  # beta.43 reads native ~/.omo config; legacy opencode sidecars are migration
  # inputs only. Explicit OMO_PROFILE also beats inherited profile selectors.
  home.file.".omo/omo.jsonc".text = builtins.toJSON {
    profiles = lib.mapAttrs (_: profile: let
      route = {
        model = "${profile.provider}/glm-5.3-flash";
        fallback_models = ["${profile.provider}/deepseek-v4-flash"];
      };
    in {
      "[opencode]" = {
        agents = lib.genAttrs agents (_: route);
        categories = lib.genAttrs categories (_: route);
      };
    }) (lib.filterAttrs (_: profile: profile.omo) profiles);
  };
  home.packages = lib.mapAttrsToList launcher profiles;
}
