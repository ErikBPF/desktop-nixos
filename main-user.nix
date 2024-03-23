 { lib, config, pkgs, ... }:
 
let
    cfg = config.main-user;
in
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
            packages = with pkgs; [
            firefox
            git
            #  thunderbird
            ];
        };
    };
}