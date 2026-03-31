{
  self,
  config,
  ...
}: let
  inherit (config) username;
in {
  flake.modules.nixos.user = {
    pkgs,
    config,
    ...
  }: {
    sops.secrets."hashed_password" = {
      sopsFile = self + "/secrets/sops/secrets.yaml";
      neededForUsers = true;
    };

    users.users.${username} = {
      isNormalUser = true;
      hashedPasswordFile = config.sops.secrets."hashed_password".path;
      shell = pkgs.fish;
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMxdE+uAvR4Nm2XwZNjTf2Ae8PlrRtnZUI6BBrbGl78u erikbogado@gmail.com"
      ];
      extraGroups = [
        "audio"
        "input"
        "networkmanager"
        "podman"
        "render"
        "sound"
        "tty"
        "video"
        "wheel"
        "docker"
        "qemu"
        "kvm"
        "libvirtd"
      ];
    };
    programs.fish.enable = true;
  };
}
