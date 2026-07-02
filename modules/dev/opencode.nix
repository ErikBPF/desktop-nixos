{inputs, ...}: {
  flake.modules.home.opencode = _: {
    imports = [inputs.opencode-flake.homeManagerModules.withPackage];

    programs.opencode-profile = {
      enable = true;
      tui.enable = true;
      rtk.enable = true;
      # The full instruction file (caveman + guidelines + doctrine + canary)
      # is ported verbatim from the previously hand-managed
      # ~/.config/opencode/AGENTS.md; profile style stays off because the
      # file already carries its own caveman section.
      agents.preamble = "";
      agents.extraText = builtins.readFile ./opencode-agents.md;
    };

    # Host-local policy (opencode-flake RFC D3): provider routing and this
    # fleet's extra guardrails stay out of the reusable profile. Ported
    # verbatim from the hand-managed opencode.json (2026-07-02). Keys come
    # from sops via laptop-opencode-client (fish sources
    # /run/secrets/opencode/*).
    programs.opencode.settings = {
      instructions = ["AGENTS.md"];
      plugin = ["./plugins/rtk.ts"];

      provider = {
        litellm = {
          npm = "@ai-sdk/openai-compatible";
          name = "Orion";
          options = {
            baseURL = "https://litellm.homelab.pastelariadev.com/v1";
            apiKey = "{env:OPENCODE_LITELLM_KEY}";
          };
          models = {
            qwen-chat = {
              name = "Qwen Chat (Orion)";
              cost = {
                input = 0.000000195;
                output = 0.00000156;
              };
              limit = {
                context = 32768;
                output = 32768;
              };
            };
            qwen-embed = {
              name = "Qwen Embed (Orion)";
              cost = {
                input = 0.00000013;
                output = 0.0;
              };
              limit = {
                context = 32768;
                output = 0;
              };
            };
          };
        };
        opencode = {
          npm = "@ai-sdk/openai-compatible";
          name = "OpenCode Zen (direct escape-hatch)";
          options = {
            baseURL = "https://opencode.ai/zen/go/v1";
            apiKey = "{env:OPENCODE_GO_KEY}";
          };
        };
        openai = {
          name = "OpenAI (ChatGPT subscription, OAuth via `opencode auth login openai`)";
          models = {
            "gpt-5.4" = {
              name = "GPT-5.4";
              limit = {
                context = 200000;
                output = 32000;
              };
            };
            "gpt-5.4-mini" = {
              name = "GPT-5.4 Mini";
              limit = {
                context = 200000;
                output = 32000;
              };
            };
            "gpt-5.5" = {
              name = "GPT-5.5";
              limit = {
                context = 200000;
                output = 32000;
              };
            };
            "gpt-5-codex" = {
              name = "GPT-5 Codex";
              limit = {
                context = 200000;
                output = 32000;
              };
            };
            "gpt-5.3-codex-spark" = {
              name = "GPT-5.3 Codex Spark";
              limit = {
                context = 200000;
                output = 32000;
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
          resource = "opencode";
        }
        {
          effect = "allow";
          action = "provider.use";
          resource = "openai";
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

      compaction = {
        auto = true;
        tail_turns = 8;
      };
      tool_output = {
        max_lines = 200;
        max_bytes = 12000;
      };
    };
  };
}
