_: {
  flake.modules.nixos.apparmor = {pkgs, ...}: {
    # AppArmor 5.0 stopped installing this helper when built with
    # DISTRO=unknown, while aa-teardown and aa-remove-unknown still source it.
    # Keep the helper in the parser output until nixpkgs carries the fix.
    nixpkgs.overlays = [
      (_final: prev: {
        apparmor-parser = prev.apparmor-parser.overrideAttrs (old: {
          # The upstream equality test blocks indefinitely in the sandbox on
          # this release. The parser sources are unchanged by this override.
          doCheck = false;
          postInstall =
            (old.postInstall or "")
            + ''
              install -Dm644 ../init/rc.apparmor.functions \
                "$out/lib/apparmor/rc.apparmor.functions"
            '';
        });
      })
    ];

    security.apparmor = {
      enable = true;
      packages = with pkgs; [
        apparmor-utils
        apparmor-profiles
      ];
    };
  };
}
