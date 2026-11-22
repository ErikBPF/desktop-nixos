let
  flake = builtins.getFlake (toString ../..);
  config = flake.nixosConfigurations.kepler.config;
  reader = config.systemd.services.harbor-reader;
  guests = flake.inputs.nixpkgs.lib.unique (map (name: "microvm@${name}.service") config.microvm.autostart);
in
  assert builtins.length guests == 6;
  assert builtins.all (guest: builtins.elem guest reader.requiredBy && builtins.elem guest reader.before) guests;
  assert builtins.all (guest: builtins.elem guest reader.wants) guests;
  assert reader.serviceConfig.Restart == "on-failure";
  assert reader.restartIfChanged == false; "KEPLER_READER_RECOVERY_EVAL_OK"
