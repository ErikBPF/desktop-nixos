{inputs, ...}: {
  flake.modules.home.opencode = {pkgs, ...}: let
    # Keep the V2 adapter: upstream 5.1.1 did not load in native runtime checks.
    ponytailV2 = pkgs.runCommand "opencode-ponytail-v2-0.1.0" {} ''
      mkdir -p "$out"
      tar -xzf ${pkgs.fetchurl {
        url = "https://registry.npmjs.org/@filecrop/opencode-ponytail-v2/-/opencode-ponytail-v2-0.1.0.tgz";
        hash = "sha512-4DgzFxuANIgCDeTOs+Xair7P7mkXNULxClxQANogqyqZBTJK+KuHRKsYZ5VFeuRw2pw1xMEQ62xst+cXXVheAg==";
      }} --strip-components=1 -C "$out"
    '';

    # graphifyy with the MCP extra. Upstream's tree-sitter grammar set is not
    # packaged in nixpkgs, so the wheels are pinned as a fixed-output
    # derivation and installed offline. Bump the version and wheels hash
    # together. The wheels output must stay free of store references, hence
    # the throwaway seed venv in $TMPDIR rather than a venv in $out.
    graphifyWheels = pkgs.stdenvNoCC.mkDerivation (finalAttrs: {
      pname = "graphify-wheels";
      version = "0.9.53";

      nativeBuildInputs = [pkgs.uv];

      buildPhase = ''
        runHook preBuild
        export HOME="$TMPDIR"
        export UV_CACHE_DIR="$TMPDIR/uv-cache"
        export SSL_CERT_FILE="${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
        export REQUESTS_CA_BUNDLE="$SSL_CERT_FILE"
        export UV_NATIVE_TLS=1
        ${pkgs.uv}/bin/uv venv --seed --python ${pkgs.python3}/bin/python "$TMPDIR/download"
        # Fix the platform tags: pip otherwise picks wheels from the build
        # host's glibc, which made the hash differ between builders.
        "$TMPDIR/download/bin/pip" download --only-binary=:all: \
          --platform manylinux_2_28_x86_64 \
          --platform manylinux2014_x86_64 \
          --platform linux_x86_64 \
          --python-version 3.14 --implementation cp \
          --abi cp314 --abi abi3 --abi none \
          --dest "$out" 'graphifyy[mcp]==${finalAttrs.version}'
        runHook postBuild
      '';

      dontFixup = true;
      dontUnpack = true;
      installPhase = "true";

      outputHashMode = "recursive";
      outputHashAlgo = "sha256";
      outputHash = "sha256-nso8eqFN6Xh5zhxMKH8xRSVRD56yOZV8CdWZyG7ylMA=";
    });

    graphify = pkgs.stdenvNoCC.mkDerivation (finalAttrs: {
      pname = "graphify";
      version = "0.9.53";

      nativeBuildInputs = [pkgs.uv];

      buildPhase = ''
        runHook preBuild
        export HOME="$TMPDIR"
        export UV_CACHE_DIR="$TMPDIR/uv-cache"
        ${pkgs.uv}/bin/uv venv --python ${pkgs.python3}/bin/python --no-seed "$out"
        ${pkgs.uv}/bin/uv pip install --python "$out/bin/python" --no-index \
          --find-links ${graphifyWheels} 'graphifyy[mcp]==${finalAttrs.version}'
        runHook postBuild
      '';

      dontFixup = true;
      dontUnpack = true;
      installPhase = "true";

      meta = {
        description = "Knowledge graph builder and MCP server for repositories";
        homepage = "https://pypi.org/project/graphifyy/";
        license = pkgs.lib.licenses.mit;
        mainProgram = "graphify";
        platforms = ["x86_64-linux"];
      };
    });
    protectedReads = [
      "*.secrets.json"
      "*.secret.json"
      "*.env*"
      ".env*"
      "*/.env*"
      "*.age"
      ".ssh/*"
      "*/.ssh/*"
      ".config/sops/age/*"
      "*/.config/sops/age/*"
      "/run/secrets/*"
    ];
    permissionRules = action: effect: resources:
      map (resource: {inherit action effect resource;}) resources;
    codexModel = name: reasoningEffort: {
      name = "${name} (Codex subscription)";
      cost = {
        input = 0;
        output = 0;
        cache_read = 0;
      };
      # Account catalog default context; reserve 32k for client output.
      limit = {
        context = 272000;
        output = 32768;
      };
      modalities = {
        input = ["text" "image"];
        output = ["text"];
      };
      reasoning = true;
      tool_call = true;
      options = {inherit reasoningEffort;};
      variants = builtins.listToAttrs (map (effort: {
        name = effort;
        value.reasoningEffort = effort;
      }) ["low" "medium" "high" "xhigh" "max"]);
    };
  in {
    imports = [
      inputs.opencode-flake.homeManagerModules.withPackageV2
    ];

    home.packages = [graphify];

    # rtk comes from modules/dev/codex.nix (hiPrio 0.48.0). Adding pkgs.rtk here
    # too put two different store paths with the same bin/rtk subpath in one
    # home-manager buildEnv and broke every rebuild.

    # Provider keys for opencode's `{env:...}` substitution. Declarative port
    # of the former hand-made ~/.config/fish/conf.d/zz-opencode-secrets.fish:
    # read the sops runtime files. LiteLLM deliberately has no plaintext
    # fallback: the old bootstrap file carried the proxy master key and could
    # silently turn an unavailable scoped credential into admin access.
    # `$(<file)` avoids the `cat`→`bat` alias mangling the key.
    programs.zsh.initContent = ''
      if [[ -r /run/secrets/opencode/litellm_key ]]; then
        export OPENCODE_LITELLM_KEY="$(</run/secrets/opencode/litellm_key)"
      fi
      if [[ -r /run/secrets/opencode/work_key ]]; then
        export OPENCODE_WORK_KEY="$(</run/secrets/opencode/work_key)"
      fi
    '';

    programs.opencode-profile = {
      enable = true;
      tui.enable = false;
      # Native ordered V2 rules below replace the profile's V1 yolo defaults.
      permissions.enable = false;
      # v1 rtk plugin; the v2 plugin lane below installs its own shim plugin.
      rtk.enable = false;
      # Instructions already carry the response style and shared repo policy.
      agents.preamble = "";
      agents.extraText = builtins.readFile ./opencode-agents.md + "\n" + builtins.readFile ./agent-policy.md;
    };

    # Host-local policy (opencode-flake RFC D3): provider routing and this
    # fleet's extra guardrails stay out of the reusable profile. Keys come
    # from sops via opencode-client (the zsh snippet above sources
    # /run/secrets/opencode/*).
    programs.opencode.settings = {
      update = "disable";
      instructions = ["AGENTS.md"];
      plugins = [
        # v2 plugin API. RTK rewrites through a shell shim so OpenCode still
        # authorizes the original command (rtk-ai/rtk#4197). Gateway headers
        # keep the LiteLLM/Work routing session header. Ponytail v2 is the
        # hash-pinned native adapter. DCP remains absent: its v2
        # token-tracking port is not verified; optional experiments are opt-in.
        "file://${./opencode-plugins-v2/rtk}"
        "file://${./opencode-plugins-v2/gateway-headers}"
        "${ponytailV2}"
      ];
      model = "litellm/deepseek-v4.1-flash";
      small_model = "litellm/deepseek-v4.1-flash";
      # 1.18.29 still uses this filter; policies cover the newer core path.
      # `opencode-go` is the direct escape hatch when the gateways are down.
      # `openai` is the Codex/ChatGPT subscription used directly (oauth).
      enabled_providers = ["litellm" "work" "opencode-go" "openai"];

      # Gateway /model/info snapshot, 2026-09-10; costs per million tokens.
      provider = {
        litellm = {
          npm = "@ai-sdk/openai-compatible";
          name = "Orion";
          options = {
            baseURL = "https://litellm.homelab.pastelariadev.com/v1";
            apiKey = "{env:OPENCODE_LITELLM_KEY}";
          };
          models = {
            "codex-gpt-6-astra" = codexModel "Astra" "low";
            "codex-gpt-5.6-sol" = codexModel "Sol" "low";
            "codex-gpt-5.6-terra" = codexModel "Terra" "medium";
            "codex-gpt-5.6-luna" = codexModel "Luna" "medium";
            "deepseek-v4.1-flash" = {
              name = "DeepSeek V4.1 Flash (LiteLLM → OpenCode Go)";
              cost = {
                input = 0.30;
                output = 1.20;
                cache_read = 0.006;
              };
              limit = {
                context = 1000000;
                output = 384000;
              };
              modalities = {
                input = ["text" "image"];
                output = ["text"];
              };
              reasoning = true;
              tool_call = true;
              options.reasoningEffort = "max";
              variants = {
                low.reasoningEffort = "low";
                high.reasoningEffort = "high";
                max.reasoningEffort = "max";
                medium.disabled = true;
              };
            };
            "glm-5.3-flash" = {
              name = "GLM-5.3 Flash (LiteLLM → OpenCode Go)";
              cost = {
                input = 0.075;
                output = 0.25;
              };
              limit = {
                context = 1000000;
                output = 131072;
              };
              reasoning = true;
              options.reasoningEffort = "max";
              variants = {
                low.reasoningEffort = "low";
                high.reasoningEffort = "high";
                max.reasoningEffort = "max";
              };
            };
            qwen-chat = {
              name = "Qwen Chat (Orion)";
              cost = {
                input = 0.25;
                output = 0.75;
              };
              limit = {
                context = 98304;
                output = 32768;
              };
            };
            "apollo-qwen38-27b" = {
              name = "Qwen3.8 27B (Apollo)";
              cost = {
                input = 0.0;
                output = 0.0;
              };
              limit = {
                context = 90000;
                input = 81808;
                output = 8192;
              };
            };
            "qwen3.8-flash" = {
              name = "Qwen3.8 Flash (LiteLLM → OpenCode Go)";
              cost = {
                input = 0.15;
                output = 0.47;
              };
              limit = {
                context = 1000000;
                output = 131072;
              };
            };
          };
        };
        work = {
          npm = "@ai-sdk/openai-compatible";
          name = "Work";
          options = {
            baseURL = "https://llm-gateway-dataplatform-dev.nstech.com.br/v1";
            apiKey = "{env:OPENCODE_WORK_KEY}";
          };
          models = {
            "chatgpt-5.6-luna" = {
              limit = {
                context = 1050000;
                input = 922000;
                output = 128000;
              };
              cost = {
                cache_read = 0.02;
                input = 0.2;
                output = 1.2;
              };
              options.reasoningEffort = "none";
              reasoning = true;
              variants.none.reasoningEffort = "none";
            };
            "chatgpt-5.6-sol" = {
              limit = {
                context = 1050000;
                input = 922000;
                output = 128000;
              };
              cost = {
                cache_read = 0.5;
                input = 4.0;
                output = 20.0;
              };
              options.reasoningEffort = "none";
              reasoning = true;
              variants.none.reasoningEffort = "none";
            };
            "chatgpt-5.6-terra" = {
              limit = {
                context = 1050000;
                input = 922000;
                output = 128000;
              };
              cost = {
                cache_read = 0.2;
                input = 2.0;
                output = 12.0;
              };
              options.reasoningEffort = "none";
              reasoning = true;
              variants.none.reasoningEffort = "none";
            };
            "deepseek-v4.1-flash" = {
              limit = {
                context = 1048576;
                output = 393216;
              };
              cost = {
                input = 0.30;
                output = 1.20;
              };
              modalities = {
                input = ["text" "image"];
                output = ["text"];
              };
              reasoning = true;
              tool_call = true;
              # Work's OpenRouter route rejects reasoning_effort; use its default.
            };
            "glm-5.3-flash" = {
              limit = {
                context = 1048576;
                output = 131072;
              };
              cost = {
                cache_read = 0.015;
                input = 0.075;
                output = 0.25;
              };
              reasoning = true;
              options = {
                reasoningEffort = "max";
                allowed_openai_params = ["reasoning_effort"];
              };
              variants = {
                low.reasoningEffort = "low";
                high.reasoningEffort = "high";
                max.reasoningEffort = "max";
              };
            };
          };
        };
        # Direct OpenCode Go subscription (models.dev supplies npm/baseURL and
        # the model catalog); bypasses the LiteLLM pool. `{file:...}` reads the
        # key at load time so every session works without shell env wiring.
        opencode-go = {
          options.apiKey = "{file:/run/secrets/opencode/zen_key}";
        };
        # Codex/ChatGPT subscription used directly via oauth (no key file, no
        # LiteLLM hop). Same account catalog as the litellm codex routes; the
        # explicit limits keep the client from over-sending context.
        openai.models = {
          "gpt-6-astra" = codexModel "Astra" "low";
          "gpt-5.6-sol" = codexModel "Sol" "low";
          "gpt-5.6-terra" = codexModel "Terra" "medium";
          "gpt-5.6-luna" = codexModel "Luna" "medium";
        };
      };

      experimental.policies =
        [
          {
            effect = "deny";
            action = "provider.use";
            resource = "*";
          }
          {
            effect = "allow";
            action = "provider.use";
            resource = "litellm";
          }
          {
            effect = "allow";
            action = "provider.use";
            resource = "work";
          }
          {
            effect = "allow";
            action = "provider.use";
            resource = "opencode-go";
          }
          {
            effect = "allow";
            action = "provider.use";
            resource = "openai";
          }
        ]
        # V2 2.0.27 renames this action; keep it aligned with the consumer pin.
        ++ permissionRules "tool.use" "deny" (map (path: "read:${path}") protectedReads);

      # Exact inspection commands only: no glob can admit cat, arbitrary git
      # arguments, or compound commands. Documented just deploys still ask.
      permissions =
        permissionRules "read" "allow" ["*"]
        ++ permissionRules "read" "deny" protectedReads
        ++ permissionRules "edit" "allow" ["*"]
        ++ permissionRules "edit" "ask" ["flake.lock"]
        ++ permissionRules "edit" "deny" ["*.sops" "*.env*" ".env*" "*/.env*" "*.age" "secrets/*"]
        # Later rules win, so this re-admits the env *template* the deny above
        # catches: .env.example enumerates keys and holds no values, while the
        # secrets-bearing .env / .env.<name> files stay denied.
        ++ permissionRules "edit" "allow" ["*.env.example"]
        ++ permissionRules "shell" "ask" ["*"]
        ++ permissionRules "shell" "allow" ["pwd" "git status" "git status --short" "git diff --stat" "git diff --name-only"]
        ++ permissionRules "shell" "deny" [
          "rm -rf /"
          "rm -rf /*"
          "rm -rf ~*"
          "docker volume rm *"
          "docker rm -f *"
          "*nixos-rebuild*--target-host*"
          "*ssh*nixos-rebuild*switch*"
          "ssh *docker compose*up*"
        ];

      # Helpers inherit the selected gateway/model. Architect remains read-only.
      agent = {
        plan = {
          temperature = 0.1;
        };
        architect = {
          description = "RFC, ADR, test-contract, seed-integrity review (spicyphus per-slice architect role). Use for grounded grill of behavior.md, test-contract drafting, and seed-vs-impl diff review. Never writes code.";
          mode = "subagent";
          temperature = 0.1;
          permission = {
            edit = "deny";
            bash = "deny";
          };
        };
      };

      mcp.donsetch = {
        type = "local";
        command = ["npx" "-y" "donsetch@4.7.4" "mcp" "--supervised"];
        enabled = true;
      };

      # Serve reads graphify-out/graph.json relative to the session working
      # directory.
      mcp.graphify = {
        type = "local";
        command = ["${graphify}/bin/graphify-mcp"];
        enabled = true;
      };

      # Search goes through the donsetch MCP server; the built-in provider
      # picker (exa/firecrawl/parallel/tavily/tinyfish) has no such backend.
      websearch = false;

      compaction = {
        auto = true;
        keep.tokens = 15000;
      };
      tool_output = {
        max_lines = 200;
        max_bytes = 12000;
      };
    };

    # HM-managed skills (`opencode-skills/`) plus slash-command wrappers for
    # the workflow skills and their dependency closure; each command loads the
    # shared skill from ~/.agents/skills or ~/.config/opencode/skills.
    xdg.configFile =
      (builtins.listToAttrs (map (n: {
          name = "opencode/skills/${n}/SKILL.md";
          value.source = ./opencode-skills/${n}/SKILL.md;
        }) [
          "tdd-slice"
          "tdd"
          "party-elicitation"
        ]))
      // (builtins.listToAttrs (map (n: {
          name = "opencode/command/${n}.md";
          value.source = ./opencode-commands/${n}.md;
        }) [
          "pl"
          "ip"
          "rv"
          "party"
          "map"
          "grill"
          "codehero"
          "cr"
          "tdd"
        ]))
      // {
        "opencode/cli.json".text = builtins.toJSON {
          "$schema" = "https://opencode.ai/v2/cli.json";
          theme = {
            name = "tokyonight";
            mode = "system";
          };
          mouse = true;
          scroll = {
            speed = 3;
            acceleration = false;
          };
          leader.timeout = 2000;
          diffs.view = "auto";
          attention = {
            notifications = true;
            sound = true;
            volume = 0.4;
            sound_pack = "opencode.default";
          };
          session.permissions = "prompt";
          tabs = {
            mode = "on";
            scope = "cwd";
            layout = "horizontal";
            indicators = "status";
          };
        };
        # Vendored `graphify install --platform opencode` output (graphifyy
        # uv-tool binary v0.9.53); re-vendor under modules/dev/graphify-skills
        # when the uv tool is bumped. v2 reads this same ~/.config/opencode
        # tree, so no separate v2 skill path is needed.
        "opencode/skills/graphify".source = ./graphify-skills/opencode;
      };
  };
}
