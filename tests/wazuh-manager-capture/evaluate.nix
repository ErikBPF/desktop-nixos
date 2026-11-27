let
  flake = builtins.getFlake (toString ../..);
  base = flake.nixosConfigurations.kepler;
  enabled =
    (base.extendModules {
      modules = [
        {
          services.wazuhManagerCapture = {
            enable = true;
            vaultAddress = "http://fixture.invalid:8200";
            roleIdFile = "/run/fixture/role-id";
            secretIdFile = "/run/fixture/secret-id";
            clusterCaFile = ./evaluate.nix;
          };
        }
      ];
    }).config;
  lib = flake.inputs.nixpkgs.lib;
  credential = "wazuh-manager-scale-credential.service";
  capture = enabled.systemd.services.wazuh-manager-capture;
  recovery = enabled.systemd.services.wazuh-manager-capture-recovery;
  rescue = enabled.systemd.services.wazuh-manager-capture-rescue;
  # Report the sets the assertions below constrain, so a reviewer can compare
  # all three modes without another evaluation.
  dependencyReport = builtins.toJSON {
    capture = {inherit (capture) requires after wants;};
    recover = {inherit (recovery) requires after wants;};
    rescue = {inherit (rescue) requires after wants;};
  };
in
  assert !base.config.services.wazuhManagerCapture.enable;
  assert !(base.config.systemd.services ? wazuh-manager-capture);
  assert !(base.config.systemd.services ? wazuh-manager-scale-credential);
  assert enabled.systemd.services.wazuh-manager-capture.wantedBy == [];
  assert !(enabled.systemd.timers ? wazuh-manager-capture);
  assert enabled.systemd.services.wazuh-manager-capture-recovery.wantedBy == ["multi-user.target"];
  assert enabled.systemd.timers.wazuh-manager-capture-rescue.wantedBy == ["timers.target"];
  assert enabled.systemd.timers.wazuh-manager-capture-rescue.timerConfig.OnUnitActiveSec == "1min";
  assert enabled.systemd.services.wazuh-manager-capture.onFailure == ["wazuh-manager-capture-recovery.service"];
  assert enabled.systemd.services.wazuh-manager-capture.serviceConfig.MemoryMax == "512M";
  assert enabled.systemd.services.wazuh-manager-capture.serviceConfig.KillMode == "control-group";
  assert lib.hasInfix "--token-file /run/wazuh-manager-scale/token" enabled.systemd.services.wazuh-manager-capture.serviceConfig.ExecStart;
  assert lib.hasInfix enabled.services.wazuhManagerCapture.transportRevision enabled.systemd.services.wazuh-manager-capture.serviceConfig.ExecStart;
  assert lib.hasInfix enabled.services.wazuhManagerCapture.transportSha256 enabled.systemd.services.wazuh-manager-capture.serviceConfig.ExecStart;
  assert builtins.elem "d /bulk/k8s/wazuh-recovery-proof 0755 root root -" enabled.systemd.tmpfiles.rules;
  # Capture must not run without a credential agent. Recovery and rescue keep
  # ordering only: a failed agent activation must not block restoring managers
  # from the token preserved at /run/wazuh-manager-scale/token.
  assert builtins.elem credential capture.requires;
  assert builtins.elem credential capture.after;
  assert !(builtins.elem credential recovery.requires);
  assert builtins.elem credential recovery.after;
  assert !(builtins.elem credential rescue.requires);
  assert builtins.elem credential rescue.after;
  assert capture.unitConfig.RequiresMountsFor == ["/fast" "/bulk"];
  assert recovery.unitConfig.RequiresMountsFor == [];
  assert rescue.unitConfig.RequiresMountsFor == [];
  assert builtins.trace dependencyReport true;
  assert builtins.elem base.pkgs.python3.outPath (map (package: package.outPath) enabled.environment.systemPackages); "S07_CAPTURE_EVAL_OK"
