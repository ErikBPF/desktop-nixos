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
    ../../modules/users/erik.nix
    ./disk-config.nix
  ];
boot.loader = {
    efi = {
        canTouchEfiVariables = true;
    };
    grub = {
        enable = true;
        efiSupport = true;
        device = "/dev/sda";
    };
    };
  services.openssh.enable = true;

  home-manager.useGlobalPkgs = true;
  home-manager.backupFileExtension = "backup";
  home-manager.extraSpecialArgs = {inherit inputs outputs;};
  home-manager.users.erik = import ./home/erik;


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

programs.hyprland = {
    enable = true;
    # set the flake package
    package = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland;
    # make sure to also set the portal package, so that they are in sync
    portalPackage = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.xdg-desktop-portal-hyprland;
  };

  system.stateVersion = "25.05";
}