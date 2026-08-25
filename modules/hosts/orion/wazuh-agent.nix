{self, ...}: {
  flake.modules.nixos.orion-wazuh-agent = {
    config,
    pkgs,
    ...
  }: let
    runtimeDir = "/run/wazuh-agent";
    stateDir = "/var/lib/wazuh-agent";
    sopsFile = self + "/secrets/sops/secrets.yaml";
    vaultConfig = pkgs.writeText "wazuh-agent-vault.hcl" ''
      pid_file = "${runtimeDir}/vault.pid"
      vault { address = "http://100.76.140.121:8200" }
      auto_auth {
        method "approle" {
          mount_path = "auth/approle"
          config = {
            role_id_file_path = "${config.sops.secrets."wazuh-agent-vault-role-id".path}"
            secret_id_file_path = "${config.sops.secrets."wazuh-agent-vault-secret-id".path}"
            remove_secret_id_file_after_reading = false
          }
        }
      }
      template {
        contents = "WAZUH_REGISTRATION_PASSWORD={{ with secret \"secret/data/platform/wazuh/wazuh-authd-pass\" }}{{ index .Data.data \"authd.pass\" }}{{ end }}\n"
        destination = "${runtimeDir}/agent.env"
        perms = "0400"
      }
    '';
  in {
    sops.secrets."wazuh-agent-vault-role-id" = {
      inherit sopsFile;
      key = "k3s_bootstrap/vault_approle_platform_role_id";
      mode = "0400";
    };
    sops.secrets."wazuh-agent-vault-secret-id" = {
      inherit sopsFile;
      key = "k3s_bootstrap/vault_approle_platform_secret_id";
      mode = "0400";
    };

    systemd.tmpfiles.rules = [
      "d ${runtimeDir} 0700 root root -"
      "d ${stateDir} 0700 root root -"
      "f ${stateDir}/client.keys 0600 999 999 -"
    ];

    systemd.services.wazuh-agent-vault = {
      description = "Render the Wazuh canary enrollment secret";
      wantedBy = ["multi-user.target"];
      before = ["podman-wazuh-agent.service"];
      after = ["network-online.target"];
      wants = ["network-online.target"];
      serviceConfig = {
        Type = "simple";
        Restart = "on-failure";
        RestartSec = "10s";
        Environment = "HOME=${runtimeDir}";
        ExecStart = "${pkgs.openbao}/bin/bao agent -config=${vaultConfig}";
        ExecStartPost = pkgs.writeShellScript "wait-for-wazuh-agent-env" ''
          for _ in {1..30}; do
            test -s ${runtimeDir}/agent.env && exit 0
            ${pkgs.coreutils}/bin/sleep 1
          done
          exit 1
        '';
      };
    };

    systemd.services.podman-wazuh-agent = {
      after = ["wazuh-agent-vault.service"];
      requires = ["wazuh-agent-vault.service"];
      serviceConfig.RuntimeDirectoryPreserve = "yes";
    };

    virtualisation.oci-containers.containers.wazuh-agent = {
      image = "docker.io/wazuh/wazuh-agent:4.14.7@sha256:150e7af098fbe34ec7d4825a0943ec2ab87525bff3d62488f104094c3354032e";
      environment = {
        WAZUH_MANAGER_SERVER = "192.168.10.250";
        WAZUH_REGISTRATION_SERVER = "192.168.10.250";
        WAZUH_MANAGER_PORT = "1514";
        WAZUH_REGISTRATION_PORT = "1515";
        WAZUH_AGENT_NAME = "orion-canary";
        WAZUH_AGENT_GROUP = "default";
      };
      environmentFiles = ["/run/wazuh-agent/agent.env"];
      volumes = [
        "${stateDir}/client.keys:/var/ossec/etc/client.keys"
      ];
      extraOptions = ["--hostname=orion"];
    };
  };
}
