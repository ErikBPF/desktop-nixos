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

    # Exact wheel URLs and hashes keep new index releases out of builds.
    # Refresh explicitly with `just update-graphify <version>`.
    graphifyLock = builtins.fromJSON (builtins.readFile ./graphify-lock.json);
    graphifyWheels = pkgs.linkFarm "graphify-wheels-${graphifyLock.version}" (map (wheel: {
        name = wheel.filename;
        path = pkgs.fetchurl {inherit (wheel) url sha256;};
      })
      graphifyLock.wheels);

    graphify = assert pkgs.lib.assertMsg (pkgs.python3.pythonVersion == graphifyLock.pythonVersion)
    "Refresh the Graphify wheel lock before changing its Python version";
      pkgs.stdenvNoCC.mkDerivation (finalAttrs: {
        pname = "graphify";
        inherit (graphifyLock) version;

        nativeBuildInputs = [pkgs.uv pkgs.autoPatchelfHook];
        buildInputs = [pkgs.stdenv.cc.cc.lib pkgs.zlib];

        buildPhase = ''
          runHook preBuild
          export HOME="$TMPDIR"
          export UV_CACHE_DIR="$TMPDIR/uv-cache"
          ${pkgs.uv}/bin/uv venv --python ${pkgs.python3}/bin/python --no-seed "$out"
          ${pkgs.uv}/bin/uv pip install --python "$out/bin/python" --no-index \
            --find-links ${graphifyWheels} 'graphifyy[mcp]==${finalAttrs.version}'
          runHook postBuild
        '';

        dontUnpack = true;
        installPhase = "true";
        doInstallCheck = true;
        installCheckPhase = ''
          runHook preInstallCheck
          ${pkgs.python3}/bin/python ${../../tests/graphify-lock/runtime.py} "$out"
          runHook postInstallCheck
        '';

        meta = {
          description = "Knowledge graph builder and MCP server for repositories";
          homepage = "https://pypi.org/project/graphifyy/";
          license = pkgs.lib.licenses.mit;
          mainProgram = "graphify";
          platforms = ["x86_64-linux"];
        };
      });

    # donsetch ships a prebuilt linux-x64 tarball (binary + libonnxruntime.so).
    # The binary dlopens libonnxruntime.so by name, so the install layout must
    # put the .so beside it and append $ORIGIN to the rpath. Refresh url/hash with
    #   nix store prefetch-file --json --hash-type sha256 <url>
    donsetchLock = {
      version = "4.7.4";
      url = "https://github.com/dondai44423/donsetch/releases/download/v4.7.4/donsetch-linux-x64.tar.gz";
      sha256 = "sha256-oe0cccYnYsfpr6b7d8xFFIUDCSZQR/9f9NIZU6XZo4E=";
    };
    donsetch = pkgs.stdenvNoCC.mkDerivation {
      pname = "donsetch";
      inherit (donsetchLock) version;
      src = pkgs.fetchurl {inherit (donsetchLock) url sha256;};
      nativeBuildInputs = [pkgs.autoPatchelfHook];
      buildInputs = [pkgs.stdenv.cc.cc.lib];
      sourceRoot = ".";
      dontConfigure = true;
      dontBuild = true;
      # autoPatchelfHook only adds rpath entries for NEEDED libraries; the
      # dlopen-only libonnxruntime.so is found via this $ORIGIN entry.
      appendRunpaths = ["$ORIGIN"];
      installPhase = ''
        runHook preInstall
        install -Dm755 donsetch "$out/bin/donsetch"
        install -Dm644 libonnxruntime.so "$out/bin/libonnxruntime.so"
        runHook postInstall
      '';
      meta = {
        description = "Search and fetch MCP server (prebuilt release binary)";
        homepage = "https://github.com/dondai44423/donsetch";
        mainProgram = "donsetch";
        platforms = ["x86_64-linux"];
      };
    };
    permissionRules = action: effect: resources:
      map (resource: {inherit action effect resource;}) resources;
    approvedModels = builtins.fromJSON (builtins.readFile ./pi-harness/src/approved-models.json);
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

    home.packages = [graphify donsetch];

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
        {
          package = "file://${./opencode-plugins-v2/model-allowlist}";
          options.models = approvedModels;
        }
        "${ponytailV2}"
      ];
      model = "litellm/deepseek-v4.1-flash";
      small_model = "litellm/deepseek-v4.1-flash";
      # 1.18.29 still uses this filter; policies cover the newer core path.
      # `opencode-go` is the direct escape hatch when the gateways are down.
      # `openai` is the Codex/ChatGPT subscription used directly (oauth).
      enabled_providers = ["litellm" "work" "opencode-go" "openai"];

      # Gateway /model/info snapshot, 2026-09-10; costs per million tokens.
      # Explicit models are applied after plugin catalog transforms.
      provider = builtins.mapAttrs (provider: settings:
        if settings ? models
        then
          settings
          // {
            models =
              builtins.intersectAttrs (builtins.listToAttrs (map (name: {
                inherit name;
                value = null;
              }) (approvedModels.${provider} or [])))
              settings.models;
          }
        else settings) {
        litellm = {
          npm = "@ai-sdk/openai-compatible";
          name = "Orion";
          options = {
            baseURL = "https://litellm.homelab.pastelariadev.com/v1";
            apiKey = "{env:OPENCODE_LITELLM_KEY}";
          };
          models = {
            "codex-gpt-6.2-astra" =
              (codexModel "Astra" "low")
              // {
                provider.npm = "@opencode/ai/providers/openai-compatible/responses";
              };
            "codex-gpt-6.2-sol" = codexModel "Sol" "low";
            "codex-gpt-6.1-terra" = codexModel "Terra" "medium";
            "codex-gpt-6-luna" = codexModel "Luna" "medium";
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
            "glm-5.3" = {
              name = "GLM-5.3 (LiteLLM → OpenCode Go)";
              cost = {
                input = 1.4;
                output = 4.4;
                cache_read = 0.26;
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
            "deepseek-flash-local" = {
              name = "DeepSeek V4.1 Flash (local)";
              cost = {
                input = 0.0;
                output = 0.0;
              };
              limit = {
                context = 262144;
                output = 8192;
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
              # Work's OpenRouter route rejects reasoning_effort outright, so the
              # client must not send it. `reasoning = false` also keeps effort
              # variants out of the picker; a stored variant would 400 again.
              reasoning = false;
              tool_call = true;
            };
            "glm-5.3" = {
              limit = {
                context = 1048576;
                output = 131072;
              };
              cost = {
                cache_read = 0.015;
                input = 0.075;
                output = 0.25;
              };
              # Same Work gateway constraint as deepseek-v4.1-flash: sending
              # reasoning_effort returns 400, so no options.reasoningEffort,
              # no allowed_openai_params and no effort variants.
              reasoning = false;
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

      # Todos are off by default in V2; long autonomous runs need the task list.
      experimental.todo = true;

      experimental.policies = [
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
      ];

      # Match Pi's coding tools: OS permissions, with no harness approval gate.
      permissions =
        permissionRules "read" "allow" ["*"]
        ++ permissionRules "edit" "allow" ["*"]
        ++ permissionRules "shell" "allow" ["*"];

      # Helpers inherit the selected gateway, model and global permissions.
      agents = {
        architect = {
          description = "RFC, ADR, test-contract, seed-integrity review (spicyphus per-slice architect role). Use for grounded grill of behavior.md, test-contract drafting, and seed-vs-impl diff review. Prefers review over implementation.";
          mode = "subagent";
        };
      };

      mcp.donsetch = {
        type = "local";
        command = ["${donsetch}/bin/donsetch" "mcp" "--supervised"];
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
          "go"
          "tdd"
        ]))
      // {
        # The V2 client rewrites cli.json when its own settings change, which
        # replaces the HM symlink with a regular file. `force` keeps activation
        # idempotent instead of failing on the clobbered target.
        "opencode/cli.json" = {
          force = true;
          text = builtins.toJSON {
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
            # Pi-equivalent coding authority also applies to interactive sessions.
            session.permissions = "autoaccept";
            session.sidebar = "auto";
            # tmux owns windowing; per-cwd tab pools leak sessions across
            # panes that share a checkout.
            tabs = {
              mode = "off";
              scope = "cwd";
              layout = "horizontal";
              indicators = "status";
            };
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
