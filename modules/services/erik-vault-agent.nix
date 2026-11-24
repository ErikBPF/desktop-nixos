{
  self,
  config,
  ...
}: let
  flakeConfig = config;
in {
  # User-scoped OpenBao renderer for Erik's workstations. It deliberately has
  # no SSH template: private keys remain sops-owned and offline.
  flake.modules.nixos.erik-vault-agent = {
    config,
    lib,
    pkgs,
    ...
  }: let
    inherit (flakeConfig) username;
    home = "/home/${username}";
    host = config.networking.hostName;
    roleFile = "/run/secrets/openbao/erik-reader-role-id";
    secretFile = "/run/secrets/openbao/erik-reader-secret-id";
    preflight = pkgs.writeShellScript "erik-vault-agent-preflight" ''
      ${pkgs.coreutils}/bin/mkdir -p ${home}/.config/gh
      while [ ! -r ${roleFile} ] || [ ! -r ${secretFile} ]; do
        ${pkgs.coreutils}/bin/sleep 1
      done
    '';
    configFile = pkgs.writeText "erik-vault-agent.hcl" ''
      pid_file = "/run/user/1000/erik-vault-agent/pid"
      vault {
        address = "https://openbao.homelab.pastelariadev.com"
      }
      auto_auth {
        method "approle" {
          mount_path = "auth/approle"
          config = {
            role_id_file_path = "${roleFile}"
            secret_id_file_path = "${secretFile}"
            remove_secret_id_file_after_reading = false
          }
        }
        sink "file" {
          config = { path = "/run/user/1000/erik-vault-agent/token", mode = 0600 }
        }
      }
      template {
        contents = <<-EOT
          github.com:
            users:
              ErikBPF:
                oauth_token: {{ with secret "secret/data/users/erik/github" }}{{ .Data.data.personal }}{{ end }}
              erikbogado-nstech:
                oauth_token: {{ with secret "secret/data/users/erik/github" }}{{ .Data.data.work }}{{ end }}
            git_protocol: ssh
            user: ErikBPF
            oauth_token: {{ with secret "secret/data/users/erik/github" }}{{ .Data.data.personal }}{{ end }}
        EOT
        destination = "${home}/.config/gh/hosts.yml"
        perms = "0600"
      }
    '';
  in {
    sops.secrets."openbao-erik-reader-role-id" = {
      sopsFile = self + "/secrets/sops/secrets.yaml";
      key = "openbao_erik_reader_${host}_role_id";
      owner = username;
      mode = "0400";
      path = roleFile;
    };
    sops.secrets."openbao-erik-reader-secret-id" = {
      sopsFile = self + "/secrets/sops/secrets.yaml";
      key = "openbao_erik_reader_${host}_secret_id";
      owner = username;
      mode = "0400";
      path = secretFile;
    };

    systemd.user.services.erik-vault-agent = {
      description = "Render Erik's GitHub hosts from OpenBao";
      wantedBy = ["default.target"];
      serviceConfig = {
        ExecStartPre = "${preflight}";
        ExecStart = "${pkgs.openbao}/bin/bao agent -config=${configFile}";
        RuntimeDirectory = "erik-vault-agent";
        RuntimeDirectoryMode = "0700";
        Restart = "always";
        RestartSec = 10;
      };
    };
  };
}
