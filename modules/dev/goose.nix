_: {
  flake.modules.home.goose = {
    config,
    lib,
    pkgs,
    ...
  }: let
    yaml = pkgs.formats.yaml {};
    json = pkgs.formats.json {};

    # Goose keeps custom provider definitions in JSON files under
    # ~/.config/goose/custom_providers (config.yaml cannot carry base_url or
    # api_key). api_key_env names the env var, not the literal; the same
    # sops-sourced vars opencode.nix already exports from /run/secrets/opencode.
    mkProvider = {
      name,
      displayName,
      baseURL,
      apiKeyEnv,
      models,
    }: {
      inherit
        name
        models
        ;
      engine = "openai_compatible";
      display_name = displayName;
      api_key_env = apiKeyEnv;
      base_url = baseURL;
      supports_streaming = true;
      requires_auth = true;
    };

    recipeNames = [
      "pl"
      "ip"
      "rv"
      "party"
      "grill"
      "map"
      "codehero"
      "tdd"
    ];

    # Goose only sees ~/.agents/skills, where the TDD skill is named
    # test-driven-development (the `tdd` skill lives in opencode's own tree).
    skillFor = n:
      if n == "tdd"
      then "test-driven-development"
      else n;

    recipeDescriptions = {
      pl = "Shape an ambiguous idea into a decision map and BDD behavior contract";
      ip = "Turn accepted behavior into a vertical-slice RED-GREEN implementation plan";
      rv = "Review and revise a plan, document, diff, or PR through independent passes";
      party = "Bounded multi-perspective elicitation without manufactured consensus";
      grill = "Pressure-test an idea, spec, or plan and improve it without writing code";
      map = "Create or maintain a decision map for ambiguous or multi-part work";
      codehero = "Independent risk-focused review perspectives (security, reliability, ...)";
      tdd = "Test-driven red-green-refactor with vertical slices";
    };

    gooseConfigFile = yaml.generate "goose-config.yaml" {
      active_provider = "litellm";
      providers = {
        litellm = {
          enabled = true;
          model = "deepseek-v4.1-flash";
          configured = true;
        };
        work = {
          enabled = true;
          model = "deepseek-v4.1-flash";
          configured = true;
        };
      };
      slash_commands =
        map (n: {
          command = n;
          recipe_path = "${config.xdg.configHome}/goose/recipes/${n}.yaml";
        })
        recipeNames;
    };

    litellmProviderFile = json.generate "litellm.json" (
      mkProvider {
        name = "litellm";
        displayName = "Orion";
        baseURL = "https://litellm.homelab.pastelariadev.com/v1/chat/completions";
        apiKeyEnv = "OPENCODE_LITELLM_KEY";
        models = [
          {
            name = "codex-gpt-6-astra";
            context_limit = 272000;
          }
          {
            name = "codex-gpt-5.6-sol";
            context_limit = 272000;
          }
          {
            name = "codex-gpt-5.6-terra";
            context_limit = 272000;
          }
          {
            name = "codex-gpt-5.6-luna";
            context_limit = 272000;
          }
          {
            name = "deepseek-v4.1-flash";
            context_limit = 1000000;
          }
          {
            name = "glm-5.3-flash";
            context_limit = 1000000;
          }
          {
            name = "qwen-chat";
            context_limit = 98304;
          }
          {
            name = "apollo-qwen38-27b";
            context_limit = 90000;
          }
          {
            name = "qwen3.8-flash";
            context_limit = 1000000;
          }
        ];
      }
      # The gateway routes deepseek-v4-flash via "Console Go", which rejects
      # requests without an x-opencode-session header (verified: 400 without,
      # 200 with). Use a static header rather than session_id_header_override:
      # the override decorator strips the header whenever goose has no session
      # id (e.g. headless `goose run`).
      // {
        headers = {
          x-opencode-session = "goose";
        };
      }
    );

    workProviderFile = json.generate "work.json" (mkProvider {
      name = "work";
      displayName = "Work";
      baseURL = "https://llm-gateway-dataplatform-dev.nstech.com.br/v1/chat/completions";
      apiKeyEnv = "OPENCODE_WORK_KEY";
      models = [
        {
          name = "chatgpt-5.6-luna";
          context_limit = 1050000;
        }
        {
          name = "chatgpt-5.6-sol";
          context_limit = 1050000;
        }
        {
          name = "chatgpt-5.6-terra";
          context_limit = 1050000;
        }
        {
          name = "deepseek-v4.1-flash";
          context_limit = 1048576;
        }
        {
          name = "glm-5.3-flash";
          context_limit = 1048576;
        }
      ];
    });

    recipeFile = n:
      yaml.generate "${n}.yaml" {
        title = "Workflow: ${n}";
        description = recipeDescriptions.${n};
        instructions = "Read and follow the skill at ~/.agents/skills/${skillFor n}/SKILL.md for this request. If no request is given, ask what to work on.";
      };

    # Goose refuses config paths behind more than one symlink
    # (MAX_SYMLINK_HOPS = 1 in crates/goose/src/config/base.rs), and Home
    # Manager links through home-manager-files -> store (two hops). So copy
    # real files into place at activation instead of linking them.
    gooseFiles =
      [
        {
          path = "config.yaml";
          src = gooseConfigFile;
        }
        {
          path = "persistent.md";
          src = ./goose-instructions.md;
        }
        {
          path = "custom_providers/litellm.json";
          src = litellmProviderFile;
        }
        {
          path = "custom_providers/work.json";
          src = workProviderFile;
        }
      ]
      ++ map (n: {
        path = "recipes/${n}.yaml";
        src = recipeFile n;
      })
      recipeNames;
  in {
    home.packages = [pkgs.goose-cli];

    # goose-only persistent instructions, re-injected every turn. Kept in a
    # goose-namespaced file (not AGENTS.md) so opencode and goose coexist:
    # neither writes into the other's instruction surface.
    home.activation.gooseConfig = lib.hm.dag.entryAfter ["writeBoundary"] ''
      config_dir="$HOME/.config/goose"
      ${pkgs.coreutils}/bin/install -d -m 0755 "$config_dir" "$config_dir/custom_providers" "$config_dir/recipes"
      ${lib.concatMapStrings (entry: ''
          ${pkgs.coreutils}/bin/rm -f "$config_dir/${entry.path}"
          run ${pkgs.coreutils}/bin/install -m 0644 ${entry.src} "$config_dir/${entry.path}"
        '')
        gooseFiles}
    '';

    # Goose agent frontmatter carries only name/description/model — it has no
    # edit/bash deny, so `architect` is a read-only persona, not an enforced
    # sandbox. Keep it advisory.
    home.file = {
      ".agents/agents/architect.md".text = ''
        ---
        name: architect
        description: RFC, ADR, test-contract, and seed-integrity review. Never writes code.
        model: codex-gpt-6-astra
        ---

        You are the architect reviewer. Ground every claim in current source,
        draft or review test contracts and ADRs, and report findings — never
        edit files.
      '';
      ".agents/agents/plan.md".text = ''
        ---
        name: plan
        description: Turn accepted behavior into a grounded implementation plan.
        model: codex-gpt-6-astra
        ---

        You are the planner. Produce vertical RED-GREEN slices with ownership,
        verification, and rollback, grounded in the current source tree.
      '';
    };

    home.sessionVariables.GOOSE_MOIM_MESSAGE_FILE = "${config.xdg.configHome}/goose/persistent.md";
  };
}
