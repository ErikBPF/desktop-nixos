{config, ...}: let
  flakeConfig = config;
in {
  # SecretSpec renders the user environment from the same per-host OpenBao
  # AppRole as erik-vault-agent. SSH keys are not part of this path.
  flake.modules.nixos.erik-secretspec = {
    config,
    pkgs,
    ...
  }: let
    inherit (flakeConfig) username;
    home = "/home/${username}";
    roleFile = "/run/secrets/openbao/erik-reader-role-id";
    secretFile = "/run/secrets/openbao/erik-reader-secret-id";
    stateFile = "${home}/.local/state/secretspec/erik.env";
    specFile = "${home}/.config/secretspec/erik.toml";
    resolve = pkgs.writeShellApplication {
      name = "erik-secretspec-resolve";
      runtimeInputs = [pkgs.coreutils pkgs.secretspec];
      text = ''
        set -eu
        state="${home}/.local/state/secretspec"
        install -d -m 0700 "$state"
        tmp="$(mktemp "$state/.erik.env.XXXXXX")"
        trap 'rm -f "$tmp"' EXIT
        BAO_ROLE_ID="$(<${roleFile})" \
        BAO_SECRET_ID="$(<${secretFile})" \
          secretspec export \
            --file ${specFile} \
            --profile erik \
            --format shell \
            --reason "${config.networking.hostName} login" > "$tmp"
        chmod 0600 "$tmp"
        mv -f "$tmp" ${stateFile}
      '';
    };
  in {
    systemd.user.services.erik-secretspec = {
      description = "Resolve Erik's OpenBao environment";
      wantedBy = ["default.target"];
      serviceConfig = {
        Type = "oneshot";
        ExecStartPre = "${pkgs.bash}/bin/bash -c 'while [ ! -r ${roleFile} ] || [ ! -r ${secretFile} ]; do ${pkgs.coreutils}/bin/sleep 1; done'";
        ExecStart = "${resolve}/bin/erik-secretspec-resolve";
        Restart = "on-failure";
        RestartSec = 30;
      };
    };

    home-manager.users.${username} = {
      home.packages = [pkgs.secretspec];
      xdg.configFile."secretspec/erik.toml".text = ''
        [project]
        name = "erik"
        revision = "1.0"

        [providers.bao_home]
        uri = "openbao://${flakeConfig.flake.fleet.hosts.discovery.tailscaleIp}:8200/secret?auth=approle&tls=false"

        [profiles.erik]
        LITELLM_HOMELAB_API_KEY = { description = "Scoped homelab LiteLLM key", ref = { item = "users/erik/env", field = "LITELLM_HOMELAB_API_KEY" }, providers = ["bao_home"] }
        LITELLM_WORK_API_KEY = { description = "Scoped work LiteLLM key", ref = { item = "users/erik/env", field = "LITELLM_WORK_API_KEY" }, providers = ["bao_home"] }
        OPENCODE_GO_KEY = { description = "OpenCode Go key", ref = { item = "users/erik/env", field = "OPENCODE_GO_KEY" }, providers = ["bao_home"] }
        LITELLM_OCR_API_KEY = { description = "OCR review key", ref = { item = "users/erik/env", field = "LITELLM_OCR_API_KEY" }, providers = ["bao_home"] }
      '';
      programs.zsh.initContent = ''
        if [[ ! -r "${stateFile}" ]]; then
          timeout 15 systemctl --user start --wait erik-secretspec >/dev/null 2>&1 || true
        fi
        if [[ -r "${stateFile}" ]]; then
          source "${stateFile}"
        fi
      '';
    };
  };
}
