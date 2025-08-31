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
    outputs.nixosModules.omarchy-config
    ../../modules/users/erik.nix
    ./disk-config.nix
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
  home-manager.users.erik = import ../../home/erik;


  environment.systemPackages = with pkgs; [
    vim
    wget
    curl
		neovim
		alacritty
		btop
		gedit
		xwallpaper
		pcmanfm
		rofi
		git
		pfetch
        neovim
  ];

	fonts.packages = with pkgs; [
		jetbrains-mono
	];

  programs.git.config = {
    user.name = "erik";
    user.email = "erikbogado@gmail.com";
  };

  system.stateVersion = "25.05";
}