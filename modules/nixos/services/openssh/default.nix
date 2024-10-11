{
  config,
  lib,
  ...
}:
with lib;
with lib.nixicle; let
  cfg = config.services.ssh;
in {
  options.services.ssh = with types; {
    enable = mkBoolOpt false "Enable ssh";
    authorizedKeys = mkOpt (listOf str) [] "The public keys to apply.";
  };

  config = mkIf cfg.enable {
    services.openssh = {
      enable = true;
      ports = [22];

      settings = {
        PasswordAuthentication = false;
        StreamLocalBindUnlink = "yes";
        GatewayPorts = "clientspecified";
      };
    };
    users.users = {
      ${config.user.name}.openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMxdE+uAvR4Nm2XwZNjTf2Ae8PlrRtnZUI6BBrbGl78u erikbogado@gmail.com"
      ];
    };
  };
}
