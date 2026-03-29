{
  inputs,
  lib,
  ...
}: {
  options.colorScheme = lib.mkOption {
    type = lib.types.attrs;
    default = inputs.nix-colors.colorSchemes.tokyo-night-dark;
    description = "nix-colors color scheme, consumed by all desktop modules";
  };
}
