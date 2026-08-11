_: {
  flake.modules.nixos.discovery-runtime-health = {pkgs, ...}: let
    metricDir = "/var/lib/node-exporter-textfile";
    vaultProbe = pkgs.writeShellScript "vault-agent-render-health" ''
      set -eu
      ready=1
      for render in \
        /run/vault-agent/discord.env \
        /run/vault-agent/shared-db.env \
        /run/vault-agent/shared-grafana.env \
        /run/vault-agent/ai-serving.env
      do
        [ -s "$render" ] || ready=0
      done
      rendered=0
      if [ -s /run/vault-agent/ai-serving.env ]; then
        rendered=$(${pkgs.coreutils}/bin/stat -c %Y /run/vault-agent/ai-serving.env)
      fi
      output=${metricDir}/vault-agent-renders.prom
      {
        printf 'vault_agent_required_renders_ready %s\n' "$ready"
        printf 'vault_agent_render_last_success_seconds %s\n' "$rendered"
      } > "$output.tmp"
      ${pkgs.coreutils}/bin/mv "$output.tmp" "$output"
    '';
    litellmPython = pkgs.writeText "litellm-semantic-probe.py" ''
      import json
      import os
      import urllib.request

      base = "http://127.0.0.1:4000"
      headers = {
          "Authorization": "Bearer " + os.environ["LITELLM_MASTER_KEY"],
          "Content-Type": "application/json",
      }
      request = urllib.request.Request(base + "/health/readiness", headers=headers)
      with urllib.request.urlopen(request, timeout=15) as response:
          health = json.load(response)
      assert health == {"status": "healthy", "db": "connected"}

      body = json.dumps({
          "model": "ha-agent-qwen4b",
          "messages": [{"role": "user", "content": "Reply OK"}],
          "max_tokens": 2,
      }).encode()
      request = urllib.request.Request(
          base + "/v1/chat/completions", data=body, headers=headers
      )
      with urllib.request.urlopen(request, timeout=75) as response:
          completion = json.load(response)
      assert completion.get("choices")
    '';
    litellmProbe = pkgs.writeShellScript "litellm-semantic-health" ''
      set -u
      output=${metricDir}/litellm-semantic.prom
      printf 'litellm_semantic_ready 0\n' > "$output.tmp"
      ${pkgs.coreutils}/bin/mv "$output.tmp" "$output"
      if docker exec -i litellm python - < ${litellmPython}; then
        printf 'litellm_semantic_ready 1\n' > "$output.tmp"
        ${pkgs.coreutils}/bin/mv "$output.tmp" "$output"
      fi
    '';
  in {
    systemd.services.vault-agent-render-health = {
      description = "Export required Vault Agent render health";
      after = ["vault-agent.service"];
      wants = ["vault-agent.service"];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${vaultProbe}";
      };
    };
    systemd.timers.vault-agent-render-health = {
      wantedBy = ["timers.target"];
      timerConfig = {
        OnBootSec = "2m";
        OnUnitActiveSec = "1m";
      };
    };

    systemd.services.litellm-semantic-health = {
      description = "Export LiteLLM DB, route, and completion readiness";
      after = ["docker.service" "vault-agent.service"];
      wants = ["docker.service" "vault-agent.service"];
      path = [pkgs.docker];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${litellmProbe}";
        TimeoutStartSec = "100s";
      };
    };
    systemd.timers.litellm-semantic-health = {
      wantedBy = ["timers.target"];
      timerConfig = {
        OnBootSec = "3m";
        OnUnitActiveSec = "5m";
      };
    };
  };
}
