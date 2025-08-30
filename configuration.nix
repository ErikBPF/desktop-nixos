{
  modulesPath,
  lib,
  pkgs,
  config,
  ...
} @ args:
{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
    (modulesPath + "/profiles/qemu-guest.nix")
    inputs.home-manager.nixosModules.default
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
  home-manager.users.erik = import ../../home/henry;


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

  users.users."erik" = {
    isNormalUser = true;
    initialPassword = "1045";
    extraGroups = [ "networkmanager" "wheel" ]; # Enable ‘sudo’ for the user.
    packages = with pkgs; [
       firefox
       vscodium
     ];
     openssh.authorizedKeys.keys =
  [
    # change this to your ssh key
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMxdE+uAvR4Nm2XwZNjTf2Ae8PlrRtnZUI6BBrbGl78u erikbogado@gmail.com"
  ] ++ (args.extraPublicKeys or []); # this
  };

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