{
  lib,
  buildNpmPackage,
  nodejs_22,
}:
# Runs the offline suite. `_package.nix` filters `test/` out of the shipped
# source, so the tests need their own derivation; CI builds this check.
buildNpmPackage {
  pname = "pi-harness-tests";
  version = "0.1.0";

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./package.json
      ./package-lock.json
      ./tsconfig.json
      ./src
      ./test
    ];
  };
  nodejs = nodejs_22;

  # Same lockfile as `_package.nix`; vitest and typescript are devDependencies.
  npmDepsHash = "sha256-DvhpGKgTtMcsg6mU+Pe49X9y9UUo0HCWwL2uCy2Fsgw=";

  # `npm run build` is `tsc`, so the check typechecks before vitest runs; vitest
  # alone transpiles and would miss a type error.
  doCheck = true;

  checkPhase = ''
    runHook preCheck
    export HOME="$TMPDIR"
    npm test
    runHook postCheck
  '';

  installPhase = "touch $out";
}
