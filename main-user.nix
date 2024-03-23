 { lib, config, pkgs, ... }:
 
let
    cfg = config.main-user
{
    options = {
        main-user.enable
            = lib.mkEnableOption "enable user module";
        main-user.userName = lib.mkOption {
            default = "mainuser";
            description = "username";
        };
    };
    config = lib.mkIf cfg.enable {
        users.users.${cfg.userName} = {
            isNormalUser = true;
            initialPassword = "test";
            extraGroups = [ "networkmanager" "wheel" ];
            shell = pkgs.zsh;
            packages = with pkgs; [
            firefox
            #  thunderbird
            ];
        };
    };
}