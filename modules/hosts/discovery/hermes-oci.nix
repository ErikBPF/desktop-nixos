{
  config,
  inputs,
  self,
  ...
}: let
  inherit (config) username; # flake-parts top-level options (meta.nix)
in {
  flake.modules.nixos.discovery-hermes-oci = {
    config,
    pkgs,
    ...
  }: let
    # Model gateway reached by name over the shared docker bridge (homelab-net),
    # exactly as the live compose config does — no TLS needed in-cluster.
    litellmUrl = "http://litellm:4000/v1";

    # rtk (Rust Token Killer) — Erik's CLI-output compressor, store-mounted into
    # the official image read-only (the agent opts in via the `rtk` skill;
    # static musl binary, no glibc dep). Bump version + hash from
    # github.com/rtk-ai/rtk releases (checksums.txt → x86_64 musl).
    rtk = pkgs.stdenvNoCC.mkDerivation rec {
      pname = "rtk";
      version = "0.42.4";
      src = pkgs.fetchurl {
        url = "https://github.com/rtk-ai/rtk/releases/download/v${version}/rtk-x86_64-unknown-linux-musl.tar.gz";
        hash = "sha256-NJdRFtoR4J5QJQHa91gUPgsi7TpCoQ62f7aTpicNnjY=";
      };
      sourceRoot = ".";
      dontConfigure = true;
      dontBuild = true;
      installPhase = ''
        runHook preInstall
        install -Dm755 rtk $out/bin/rtk
        runHook postInstall
      '';
      meta.platforms = ["x86_64-linux"];
    };
  in {
    imports = [inputs.hermes-flake.nixosModules.hermes-agent-oci];

    # sops dotenv with UPSTREAM-BARE names (no HERMES_ bridge on the OCI path):
    # OPENAI_API_KEY, API_SERVER_KEY, TELEGRAM_BOT_TOKEN, DISCORD_BOT_TOKEN,
    # EXA_API_KEY. Read by the docker daemon (root) at container start.
    # NOTE (cutover pre-step): the existing secret carries the namespaced
    # HERMES_TELEGRAM_BOT_TOKEN / HERMES_DISCORD_BOT_TOKEN (the compose remapped
    # them); add the bare TELEGRAM_BOT_TOKEN / DISCORD_BOT_TOKEN before switch or
    # Telegram/Discord stay silent. See the cutover runbook.
    sops.secrets."hermes_agent/server_env" = {
      sopsFile = self + "/secrets/sops/secrets.yaml";
      format = "yaml";
      key = "hermes_agent/server_env";
      mode = "0400";
      path = "/run/secrets/hermes-agent";
      restartUnits = ["docker-hermes-agent.service"];
    };

    services.hermes-agent-oci = {
      enable = true;
      backend = "docker";
      # Keep the container name + ports so SWAG (hermes.* → hermes-agent:8642)
      # and the tailnet/host clients keep working unchanged across the cutover.
      containerName = "hermes-agent";
      image = "nousresearch/hermes-agent:latest";
      # Reuse the existing live state dir (restic-backed btrfs subvol):
      # memories, sessions, skills, lazy venv survive the Docker→OCI swap.
      hostDataDir = "/home/${username}/homelab/apps/hermes-agent";
      environmentFile = config.sops.secrets."hermes_agent/server_env".path;

      # Container binds 0.0.0.0 (API_SERVER_HOST) so SWAG + litellm reach it
      # over homelab-net by name — but do NOT publish to the host (publishPorts
      # below). With local/unsandboxed terminal + YOLO, a host-published API is
      # autonomous-command-exec surface on the LAN; SWAG (with its key/TLS) is
      # the only ingress we want.
      openBindAddress = "0.0.0.0";
      publishPorts = false;
      apiPort = 8642;
      webhookPort = 8644;
      openaiBaseUrl = litellmUrl;
      telegramAllowedUsers = [7729797827];
      memoryMax = "2g";

      # Join the shared bridge so the agent reaches litellm by name AND SWAG
      # reaches the agent by name. Mandatory — litellm/swag/hermes all live here.
      networks = ["homelab-net"];

      extraVolumes = [
        "${rtk}/bin/rtk:/usr/local/bin/rtk:ro"
        "/home/${username}/hermes-skills/meta:/opt/skills-meta:ro"
        "/home/${username}/hermes-skills/research:/opt/skills-research:ro"
        # Native hermes plugin: pre_tool_call rewrites terminal commands to
        # `rtk <cmd>` (output compressed before entering context). Read-only
        # store mount into the plugin search dir (~/.hermes/plugins = /opt/data
        # /plugins); enabled via settings.plugins.enabled below.
        "${./hermes-plugins/rtk-rewrite}:/opt/data/plugins/rtk-rewrite:ro"
        # Native LLM-wiki base: a clone of vault.git @ `hermes` branch (Karpathy
        # AGENTS.md schema), bootstrapped declaratively by discovery-hermes-wiki
        # (sops deploy key + clone oneshot + cron seed). The clone + key are NO
        # longer manual host state. git ssh is scoped to this repo via
        # core.sshCommand (set by the clone oneshot, points at /opt/wiki-key).
        "/var/lib/hermes-wiki:/opt/wiki:rw"
        ''${config.sops.secrets."hermes_wiki/deploy_key".path}:/opt/wiki-key:ro''
      ];

      extraEnvironment = {
        # Discord allow-list has no typed wrapper option; set the bare env var.
        DISCORD_ALLOWED_USERS = "319270715129856010";
        # YOLO: bypass the per-command dangerous-command approval gate (which is
        # frozen at process import and keys off this env var). Pairs with
        # approvals.mode = "off" below. hermes' hardcoded catastrophic floor
        # (rm -rf /, mkfs, shutdown, …) still blocks regardless. Needed because
        # config.yaml is mounted :ro, so a runtime "always" choice can't persist
        # (the "Could not save allowlist: Read-only file system" warning) —
        # declarative is the only durable path.
        HERMES_YOLO_MODE = "1";
      };

      # Canonical persona (single-sourced; same file the live deploy mirrors).
      soulFile = ./romozina-SOUL.md;

      # Homelab settings overlaid on the flake's vendor-neutral config.yaml.nix
      # defaults — migrated verbatim from the live servarr config.yaml so the
      # cutover is behavior-preserving. Defaults already cover compression,
      # guardrails, session_reset, browser, delegation, stt, privacy, agent,
      # terminal, platforms — only the deltas are set here.
      settings = {
        # Brain: GLM-5.2 via LiteLLM (opencode Go, flat-rate). context_length
        # left unset on purpose — hermes auto-detects each aliased model's
        # window from LiteLLM.
        model = {
          provider = "custom";
          default = "glm-5";
          base_url = litellmUrl;
          api_key = "\${OPENAI_API_KEY}";
        };

        # Aux models — vision on qwen, compression/session-search on MiMo (free)
        # to keep the shared budget for actual responses.
        auxiliary = {
          vision = {
            provider = "custom";
            model = "qwen-chat";
            base_url = litellmUrl;
            api_key = "\${OPENAI_API_KEY}";
          };
          compression = {
            provider = "custom";
            model = "mimo";
            base_url = litellmUrl;
            api_key = "\${OPENAI_API_KEY}";
          };
          session_search = {
            provider = "custom";
            model = "mimo";
            base_url = litellmUrl;
            api_key = "\${OPENAI_API_KEY}";
          };
        };

        # Raised caps (defaults are ~800/500 tok). Auto-injected every turn —
        # see proposal §1; tune down if the shared budget bites.
        memory = {
          memory_char_limit = 10000;
          user_char_limit = 3000;
        };

        # Git-versioned read-only skills (hermes-skills repo), mounted at
        # /opt/skills-ext above. Local /opt/data/skills wins on name collision.
        skills.external_dirs = ["/opt/skills-meta" "/opt/skills-research"];

        # Permanent auto-approve (declarative). The runtime "always" choice can't
        # persist (config.yaml is :ro), so set it here. Covers the non-command
        # approval paths; the shell-command gate is HERMES_YOLO_MODE above.
        approvals.mode = "off";

        # Opt-in the rtk-rewrite plugin (mounted at /opt/data/plugins above).
        # Plugins are opt-in by default; only names listed here load.
        plugins.enabled = ["rtk-rewrite"];

        # /model <alias> switches — all routed through LiteLLM.
        model_aliases = {
          qwen = {
            model = "qwen-chat";
            provider = "custom";
            base_url = litellmUrl;
          };
          glm = {
            model = "glm-5";
            provider = "custom";
            base_url = litellmUrl;
          };
          kimi = {
            model = "kimi-k2-code";
            provider = "custom";
            base_url = litellmUrl;
          };
          qwen-max = {
            model = "qwen3-max";
            provider = "custom";
            base_url = litellmUrl;
          };
          minimax = {
            model = "minimax-m2";
            provider = "custom";
            base_url = litellmUrl;
          };
          mimo = {
            model = "mimo";
            provider = "custom";
            base_url = litellmUrl;
          };
          mimo-pro = {
            model = "mimo-pro";
            provider = "custom";
            base_url = litellmUrl;
          };
        };
      };
    };

    # No host firewall rules here: ports aren't published to the host
    # (publishPorts = false), and docker would bypass the nixos firewall anyway.
    # SWAG over homelab-net is the only ingress.
  };
}
