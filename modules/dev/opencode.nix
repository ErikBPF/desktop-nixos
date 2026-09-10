{inputs, ...}: {
  flake.modules.home.opencode = {pkgs, ...}: {
    imports = [inputs.opencode-flake.homeManagerModules.withPackage ./_opencode-profiles.nix];

    home.packages = [pkgs.rtk];

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
      tui.enable = true;
      rtk.enable = true;
      # Instructions already carry the response style and shared repo policy.
      agents.preamble = "";
      agents.extraText = builtins.readFile ./opencode-agents.md;
    };

    # Host-local policy (opencode-flake RFC D3): provider routing and this
    # fleet's extra guardrails stay out of the reusable profile. Keys come
    # from sops via opencode-client (the zsh snippet above sources
    # /run/secrets/opencode/*).
    programs.opencode.settings = {
      instructions = ["AGENTS.md"];
      plugin = [
        "./plugins/rtk.ts"
        "${inputs.ponytail}/.opencode/plugins/ponytail.mjs"
        # Context pruning: dedups tool outputs, purges stale errors, lets the
        # model compress ranges. Version pinned exactly — floating specs would
        # trigger the plugin's self-rm-rf auto-update path (audited 2026-09-05).
        "@tarquinen/opencode-dcp@3.1.15"
        # Custom providers need Go's session header as well as OpenCode's native headers.
        "./plugins/gateway-headers.mjs"
      ];
      model = "litellm/deepseek-flash";
      small_model = "litellm/deepseek-flash";
      # 1.18.29 still uses this filter; policies cover the newer core path.
      enabled_providers = ["litellm" "work"];

      # Gateway /model/info snapshot, 2026-09-07; costs per million tokens.
      provider = {
        litellm = {
          npm = "@ai-sdk/openai-compatible";
          name = "Orion";
          options = {
            baseURL = "https://litellm.homelab.pastelariadev.com/v1";
            apiKey = "{env:OPENCODE_LITELLM_KEY}";
          };
          models = {
            deepseek-flash = {
              name = "DeepSeek V4.1 Flash (LiteLLM → OpenCode Go)";
              cost = {
                input = 0.15;
                output = 0.6;
                cache_read = 0.003;
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
            };
            deepseek-v4-flash = {
              name = "DeepSeek V4 Flash (LiteLLM → OpenCode Go)";
              cost = {
                cache_read = 0.014;
                input = 0.14;
                output = 0.28;
              };
              limit = {
                context = 1000000;
                output = 384000;
              };
            };
            deepseek-v4-pro = {
              name = "DeepSeek V4 Pro (LiteLLM → OpenCode Go)";
              cost = {
                cache_read = 0.044;
                input = 1.74;
                output = 3.84;
              };
              limit = {
                context = 1000000;
                output = 384000;
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
                context = 922000;
                output = 128000;
              };
              cost = {
                cache_read = 0.02;
                input = 0.2;
                output = 1.2;
              };
              options.reasoningEffort = "none";
            };
            "chatgpt-5.6-sol" = {
              limit = {
                context = 922000;
                output = 128000;
              };
              cost = {
                cache_read = 0.5;
                input = 4.0;
                output = 20.0;
              };
              options.reasoningEffort = "none";
            };
            "chatgpt-5.6-terra" = {
              limit = {
                context = 922000;
                output = 128000;
              };
              cost = {
                cache_read = 0.2;
                input = 2.0;
                output = 12.0;
              };
              options.reasoningEffort = "none";
            };
            "deepseek-v4-flash" = {
              limit = {
                context = 1024000;
                output = 384000;
              };
              cost = {
                input = 0.22;
                output = 0.66;
              };
            };
            "deepseek-v4-pro" = {
              limit = {
                context = 1024000;
                output = 384000;
              };
              cost = {
                input = 0.87;
                output = 1.74;
              };
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
            };
          };
        };
      };

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
      ];

      # Extends the profile's G1 rules with this host's extra denies and the
      # bare-glob variants the hand-managed config used.
      permission = {
        "*" = "allow";
        edit = {
          "*.sops" = "deny";
          "*.env*" = "deny";
          "*.age" = "deny";
        };
        bash = {
          "rm -rf /" = "deny";
          "docker rm -f *" = "deny";
          "*nixos-rebuild*--target-host*" = "deny";
          "**ssh*nixos-rebuild*switch*" = "deny";
        };
      };

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

      compaction = {
        auto = true;
        tail_turns = 8;
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
          "tdd"
        ]))
      // {
        "opencode/plugins/gateway-headers.mjs".source = ./opencode-plugins/gateway-headers.mjs;
        # Vendored `graphify install --platform opencode` output (graphifyy
        # uv-tool binary v0.9.53); re-vendor under modules/dev/graphify-skills
        # when the uv tool is bumped.
        "opencode/skills/graphify".source = ./graphify-skills/opencode;
      };
  };
}
