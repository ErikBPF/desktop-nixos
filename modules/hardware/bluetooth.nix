_: {
  flake.modules.nixos.bluetooth = _: {
    hardware.bluetooth = {
      enable = true;
      powerOnBoot = true;
      settings = {
        General = {
          Experimental = true;
          Enable = "Source,Sink,Media,Socket";
        };
      };
    };
    services.blueman.enable = true;
  };
}
