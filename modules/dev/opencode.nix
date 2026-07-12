{inputs, ...}: {
  flake.modules.home.opencode = _: {
    imports = [inputs.opencode-flake.homeManagerModules.withPackage];

    # Provider keys for opencode's `{env:...}` substitution. Declarative port
    # of the former hand-made ~/.config/fish/conf.d/zz-opencode-secrets.fish:
    # read the sops runtime files, falling back to ~/.config/opencode/secrets.env
    # during bootstrap. Guarded by `-r`, so it is a no-op on hosts that don't
    # ship the secret. `$(<file)` avoids the `cat`→`bat` alias mangling the key.
    programs.zsh.initContent = ''
      if [[ -r /run/secrets/opencode/litellm_key ]]; then
        export OPENCODE_LITELLM_KEY="$(</run/secrets/opencode/litellm_key)"
      elif [[ -r "$HOME/.config/opencode/secrets.env" ]]; then
        export OPENCODE_LITELLM_KEY="$(grep '^OPENCODE_LITELLM_KEY=' "$HOME/.config/opencode/secrets.env" | cut -d= -f2-)"
      fi
      if [[ -r /run/secrets/opencode/zen_key ]]; then
        export OPENCODE_GO_KEY="$(</run/secrets/opencode/zen_key)"
      elif [[ -r "$HOME/.config/opencode/secrets.env" ]]; then
        export OPENCODE_GO_KEY="$(grep '^OPENCODE_GO_KEY=' "$HOME/.config/opencode/secrets.env" | cut -d= -f2-)"
      fi
    '';

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
    # from sops via laptop-opencode-client (the zsh snippet above sources
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
            # OpenCode Zen free tier (Homelab workspace, 100 req/day, $0) via the
            # litellm zen-free* routes. deepseek is a heavy reasoner — prefer pickle.
            zen-free = {
              name = "Zen Free — DeepSeek V4 Flash (free, reasoner)";
              cost = {
                input = 0.0;
                output = 0.0;
              };
              limit = {
                context = 163840;
                output = 8192;
              };
            };
            zen-free-pickle = {
              name = "Zen Free — Big Pickle (free, coder)";
              cost = {
                input = 0.0;
                output = 0.0;
              };
              limit = {
                context = 204800;
                output = 8192;
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

      # Per-agent model routing (spicyphus per-slice loop): the architect
      # pins high-reason GLM for RFC/grill/test-contract/seed-integrity
      # review; the executor subagents pin MiMo coder for red tests + green
      # impl + read-only exploration. `plan` mirrors `architect`; `build`
      # inherits session-wide model (no override). Spec + active model list
      # discoverable via `opencode models opencode-go`.
      agent = {
        plan = {
          model = "opencode-go/glm-5.2";
          temperature = 0.1;
        };
        architect = {
          description = "RFC, ADR, test-contract, seed-integrity review (spicyphus per-slice architect role). Use for grounded grill of behavior.md, test-contract drafting, and seed-vs-impl diff review. Never writes code.";
          mode = "subagent";
          model = "opencode-go/glm-5.2";
          temperature = 0.1;
          permission = {
            edit = "deny";
            bash = "deny";
          };
        };
        general = {
          model = "opencode-go/mimo-v2.5-pro";
          temperature = 0.2;
        };
        explore = {
          model = "opencode-go/mimo-v2.5";
          temperature = 0.1;
        };
      };

      # Spicyphus per-slice TDD skill — declarative install via HM
      # `xdg.configFile` so opencode discovers it under
      # `~/.config/opencode/skills/tdd-slice/SKILL.md` (opencode-native path).
      # Source-of-truth is `modules/dev/opencode-skills/tdd-slice/SKILL.md`.
      # Never hand-edit `~/.agents/skills/tdd-slice/` or
      # `~/.config/opencode/skills/tdd-slice/` — both are HM-managed.
      xdg.configFile."opencode/skills/tdd-slice/SKILL.md".source =
        ./opencode-skills/tdd-slice/SKILL.md;

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
