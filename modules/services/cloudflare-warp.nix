_: {
  flake.modules.nixos.cloudflare-warp = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.modules.services.cloudflare-warp;
  in {
    options.modules.services.cloudflare-warp.enable = lib.mkEnableOption "Cloudflare WARP" // {default = true;};

    config = lib.mkIf cfg.enable {
      systemd.packages = [pkgs.cloudflare-warp];
      systemd.services.warp-svc.wantedBy = ["multi-user.target"];
      environment.systemPackages = [pkgs.cloudflare-warp];
    };
  };
}
