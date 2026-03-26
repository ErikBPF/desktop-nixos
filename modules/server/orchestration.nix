{...}: {
  flake.modules.nixos.orchestration = {...}: {
    # Container orchestration defaults for server hosts
    virtualisation.docker = {
      enable = true;
      enableOnBoot = true;
      autoPrune = {
        enable = true;
        dates = "weekly";
      };
    };
  };
}
