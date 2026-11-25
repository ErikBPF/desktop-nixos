{inputs, ...}: {
  # pi — second agent harness, installed alongside opencode as a shadow.
  # opencode stays the default; this module only adds the binary and its agent
  # directory. Pi has no permission system, and this profile does not port
  # opencode's (see homelab docs/proposals/2026-11-22-pi-shadow-harness.md).
  flake.modules.home.pi = {pkgs, ...}: let
    # Keep in sync with modules/dev/opencode.nix; extract when that file may change.
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

    pi = inputs.pi.packages.${pkgs.stdenv.hostPlatform.system}.pi;
    # Local durable harness (Pi-native orchestration, code mode, subagents).
    # Registered as a flake package too, but the home profile needs it on PATH.
    # It has no interactive mode, so the upstream agent keeps the `pi` command.
    piHarness = pkgs.callPackage ./pi-harness/_package.nix {};
    approvedModels = builtins.fromJSON (builtins.readFile ./pi-harness/src/approved-models.json);
  in {
    home.packages = [pi piHarness];

    # Pi reads its user-level configuration from ~/.pi/agent. Values mirror
    # modules/dev/opencode.nix; keys resolve at load time through `!cat`, so no
    # secret value lands in the store or in this repository.
    home.file = {
      ".pi/agent/settings.json".text = builtins.toJSON {
        "$schema" = "https://pi.dev/schemas/settings.schema.json";
        defaultTools = ["+codemode" "+grep" "+find" "+ls"];
        enableInstallTelemetry = false;
        defaultProjectTrust = "never";
        packages = ["npm:@dietrichgebert/ponytail@4.8.4"];
        extensions = [];
        shellPath = "/run/current-system/sw/bin/zsh";
        defaultProvider = "litellm";
        defaultModel = "deepseek-v4.1-flash";
        enabledModels = builtins.concatLists (builtins.attrValues (builtins.mapAttrs (provider: models:
          map (model: "${
            if provider == "openai"
            then "openai-codex"
            else provider
          }/${model}")
          models)
        approvedModels));
      };

      ".pi/agent/models.json".text = ''
        {
          "providers": {
            "litellm": {
              "baseUrl": "https://litellm.homelab.pastelariadev.com/v1",
              "api": "openai-completions",
              "apiKey": "!cat /run/secrets/opencode/litellm_key",
              "models": [
                {
                  "id": "deepseek-v4.1-flash",
                  "name": "DeepSeek V4.1 Flash (LiteLLM → OpenCode Go)",
                  "cost": {"input": 0.30, "output": 1.20, "cacheRead": 0.006, "cacheWrite": 0},
                  "contextWindow": 1000000,
                  "maxTokens": 384000,
                  "input": ["text", "image"],
                  "reasoning": true
                },
                {
                  "id": "glm-5.3",
                  "name": "GLM-5.3 (LiteLLM → OpenCode Go)",
                  "cost": {"input": 1.4, "output": 4.4, "cacheRead": 0.26, "cacheWrite": 0},
                  "contextWindow": 1000000,
                  "maxTokens": 131072,
                  "reasoning": true
                },
                {"id":"codex-gpt-6-astra","name":"Astra (Codex via LiteLLM)","api":"openai-responses","cost":{"input":0,"output":0,"cacheRead":0,"cacheWrite":0},"contextWindow":272000,"maxTokens":32768,"input":["text","image"],"reasoning":true},
                {"id":"codex-gpt-5.6-sol","name":"Sol (Codex via LiteLLM)","cost":{"input":0,"output":0,"cacheRead":0,"cacheWrite":0},"contextWindow":272000,"maxTokens":32768,"input":["text","image"],"reasoning":true},
                {"id":"codex-gpt-5.6-terra","name":"Terra (Codex via LiteLLM)","cost":{"input":0,"output":0,"cacheRead":0,"cacheWrite":0},"contextWindow":272000,"maxTokens":32768,"input":["text","image"],"reasoning":true},
                {"id":"codex-gpt-5.6-luna","name":"Luna (Codex via LiteLLM)","cost":{"input":0,"output":0,"cacheRead":0,"cacheWrite":0},"contextWindow":272000,"maxTokens":32768,"input":["text","image"],"reasoning":true}
              ]
            },
            "work": {
              "baseUrl": "https://llm-gateway-dataplatform-dev.nstech.com.br/v1",
              "api": "openai-completions",
              "apiKey": "!cat /run/secrets/opencode/work_key",
              "models": [
                {
                  "id": "deepseek-v4.1-flash",
                  "name": "DeepSeek V4.1 Flash (Work)",
                  "cost": {"input": 0.30, "output": 1.20, "cacheRead": 0, "cacheWrite": 0},
                  "contextWindow": 1048576,
                  "maxTokens": 393216,
                  "input": ["text", "image"],
                  "reasoning": false,
                  "compat": {"supportsReasoningEffort": false}
                },
                {
                  "id": "glm-5.3-flash",
                  "name": "GLM-5.3 Flash (Work)",
                  "cost": {"input": 0.075, "output": 0.25, "cacheRead": 0.015, "cacheWrite": 0},
                  "contextWindow": 1048576,
                  "maxTokens": 131072,
                  "reasoning": false,
                  "compat": {"supportsReasoningEffort": false}
                },
                {"id":"chatgpt-5.6-luna","cost":{"input":0.2,"output":1.2,"cacheRead":0.02,"cacheWrite":0},"contextWindow":1050000,"maxTokens":128000,"input":["text","image"],"reasoning":false,"compat":{"supportsReasoningEffort":false}},
                {"id":"chatgpt-5.6-sol","cost":{"input":4,"output":20,"cacheRead":0.5,"cacheWrite":0},"contextWindow":1050000,"maxTokens":128000,"input":["text","image"],"reasoning":false,"compat":{"supportsReasoningEffort":false}},
                {"id":"chatgpt-5.6-terra","cost":{"input":2,"output":12,"cacheRead":0.2,"cacheWrite":0},"contextWindow":1050000,"maxTokens":128000,"input":["text","image"],"reasoning":false,"compat":{"supportsReasoningEffort":false}}
              ]
            },
            "opencode-go": {
              "apiKey": "!cat /run/secrets/opencode/zen_key"
            }
          }
        }
      '';

      ".pi/agent/mcp.json".text = ''
        {
          "mcpServers": {
            "donsetch": {
              "command": "${donsetch}/bin/donsetch",
              "args": ["mcp", "--supervised"]
            },
            "graphify": {
              "command": "${graphify}/bin/graphify-mcp"
            }
          }
        }
      '';

      # Pi discovers ~/.pi/agent/extensions/*.js.
      ".pi/agent/extensions/rtk.js".source = ./pi-extensions/rtk.js;
      ".pi/agent/extensions/session-header.js".source = ./pi-extensions/session-header.js;
    };
  };
}
