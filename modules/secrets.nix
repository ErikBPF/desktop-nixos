{lib, ...}: {
  options.secrets = lib.mkOption {
    type = lib.types.attrs;
    default = builtins.fromJSON (builtins.readFile ../secrets/crypt/secrets.json);
    description = "Decrypted git-crypt secrets, available at eval time";
  };
}
