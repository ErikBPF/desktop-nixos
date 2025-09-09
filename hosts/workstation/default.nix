{
  inputs,
  outputs,
  lib,
  config,
  pkgs,
  modulesPath,
  ...
} @ args:
{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
    (modulesPath + "/profiles/qemu-guest.nix")
    inputs.home-manager.nixosModules.default
    inputs.disko.nixosModules.disko
    (import ../../modules/nixos/default.nix inputs)
    ./hardware-configuration.nix
    ../../modules/users/erik.nix
    ./disk-config.nix

    ../common/global.nix
    ../common/packages.nix
  ];
boot = {
    kernelParams = ["nohibernate"];
    tmp.cleanOnBoot = true;
    supportedFilesystems = ["ntfs"];
    loader = {
      efi.canTouchEfiVariables = true;
      grub = {
        device = "nodev";
        efiSupport = true;
        enable = true;
        useOSProber = true;
        timeoutStyle = "menu";
      };
      timeout = 300;
    };
};

  services.openssh.enable = true;

  home-manager.useGlobalPkgs = true;
  home-manager.backupFileExtension = "backup";
  home-manager.extraSpecialArgs = {inherit inputs outputs;};
  
  home-manager.users.erik = {
    imports = [
      ../../home/erik
      inputs.nix-colors.homeManagerModules.default
      inputs.sops-nix.homeManagerModules.sops
      ../../modules/home-manager/default.nix
    ];
    colorScheme = inputs.nix-colors.colorSchemes.tokyo-night-dark;
  };


  sops = {
  age.keyFile = "/home/erik/.config/sops/age/keys.txt";
  defaultSopsFormat = "yaml";
  defaultSopsFile = ../../secrets/secrets.yaml;
  secrets = {
    password ={
     sopsFile = ../../secrets/secrets.yaml;
    };
    };
  };

    systemd.services."test" = {
    script = ''
        echo "
        Hey bro! I'm a service, and imma send this secure password:
        $(cat ${config.sops.secrets.password.path})
        located in:
        ${config.sops.secrets.password.path}
        to database and hack the mainframe
        " > /home/erik/Downloads/test
      '';
    };

  system.stateVersion = "25.05";
}