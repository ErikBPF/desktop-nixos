{inputs, ...}: {
  flake.modules.home.opencode = _: {
    imports = [inputs.opencode-flake.homeManagerModules.withPackage];

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
    # from sops via opencode-client (the zsh snippet above sources
    # /run/secrets/opencode/*).
    programs.opencode.settings = {
      instructions = ["AGENTS.md"];
      plugin = [
        "./plugins/rtk.ts"
        "${inputs.ponytail}/.opencode/plugins/ponytail.mjs"
      ];
      model = "litellm/glm-5";

      provider = {
        litellm = {
          npm = "@ai-sdk/openai-compatible";
          name = "Orion";
          options = {
            baseURL = "https://litellm.homelab.pastelariadev.com/v1";
            apiKey = "{env:OPENCODE_LITELLM_KEY}";
          };
          models = {
            glm-5 = {
              name = "GLM-5.2 (LiteLLM → OpenCode Go)";
              cost = {
                input = 0.0000014;
                output = 0.0000044;
              };
              limit = {
                context = 1000000;
                output = 131072;
              };
            };
            mimo = {
              name = "MiMo V2.5 (LiteLLM → OpenCode Go)";
              cost = {
                input = 0.00000014;
                output = 0.00000028;
              };
              limit = {
                context = 1000000;
                output = 128000;
              };
            };
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
      # discoverable via `opencode models litellm`.
      agent = {
        plan = {
          model = "litellm/glm-5";
          temperature = 0.1;
        };
        architect = {
          description = "RFC, ADR, test-contract, seed-integrity review (spicyphus per-slice architect role). Use for grounded grill of behavior.md, test-contract drafting, and seed-vs-impl diff review. Never writes code.";
          mode = "subagent";
          model = "litellm/glm-5";
          temperature = 0.1;
          permission = {
            edit = "deny";
            bash = "deny";
          };
        };
        general = {
          model = "litellm/mimo";
          temperature = 0.2;
        };
        explore = {
          model = "litellm/mimo";
          temperature = 0.1;
        };
      };

      # Per-slice skills HM-managed at `~/.config/opencode/skills/<name>/SKILL.md`
      # via `xdg.configFile`. Sources-of-truth under
      # `modules/dev/opencode-skills/<name>/SKILL.md`.
      #
      # `tdd-slice`: spicyphus per-slice 6-step loop (seed→grill→contract→
      #   red tests→green impl→seed-integrity review+lessons); multi-model
      #   dispatch (GLM architect + mimo general) + 3-retry self-improve cap.
      # `tdd`: red-green-refactor discipline mechanics (one cycle per
      #   vertical slice, never refactor while RED). Adapted from
      #   obra/superpowers' bundled tdd skill — imposed declaratively here
      #   after extraction, replacing the prior hand-installed
      #   `~/.agents/skills/tdd/`.
      # `party-elicitation`: multi-persona facilitator — picks 2-3
      #   personas (Architect/Skeptic/Builder/PM/QA/Maintainer) per turn,
      #   in-character cross-talk, exits on E. Genericized from BMAD
      #   party-mode (no _bmad paths, no agent-manifest.csv, no bmad-speak.sh
      #   hook) — the only BMAD skill we extracted before Phase-2 bulk
      #   removal.
      compaction = {
        auto = true;
        tail_turns = 8;
      };
      tool_output = {
        max_lines = 200;
        max_bytes = 12000;
      };
    };

    xdg.configFile."opencode/skills/tdd-slice/SKILL.md".source =
      ./opencode-skills/tdd-slice/SKILL.md;
    xdg.configFile."opencode/skills/tdd/SKILL.md".source =
      ./opencode-skills/tdd/SKILL.md;
    xdg.configFile."opencode/skills/party-elicitation/SKILL.md".source =
      ./opencode-skills/party-elicitation/SKILL.md;
  };
}
