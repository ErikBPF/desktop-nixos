{
  inputs,
  lib,
  ...
}: {
  perSystem = {system, ...}: let
    pkgs = import inputs.nixpkgs {
      inherit system;
      config.allowUnfreePredicate = pkg: lib.getName pkg == "docker-sbx";
    };
  in
    lib.optionalAttrs (system == "x86_64-linux") {
      packages.sbx = pkgs.stdenvNoCC.mkDerivation rec {
        pname = "docker-sbx";
        version = "0.39.0";

        src = pkgs.fetchurl {
          url = "https://github.com/docker/sbx-releases/releases/download/v${version}/DockerSandboxes-linux-amd64.tar.gz";
          hash = "sha256-LsRbx5OMIML0Bv6MxyKUrVqVS9wEdgFIS4m/GhCDEdQ=";
        };

        sourceRoot = "docker-sbx";

        nativeBuildInputs = [
          pkgs.autoPatchelfHook
          pkgs.makeWrapper
        ];

        buildInputs = [
          pkgs.glibc
          pkgs.lz4
          pkgs.stdenv.cc.cc.lib
          pkgs.xxhash
          pkgs.zlib
          pkgs.zstd
        ];

        installPhase = ''
          runHook preInstall

          install -Dm755 sbx "$out/bin/sbx"
          install -Dm755 containerd-shim-nerdbox-v1 "$out/libexec/containerd-shim-nerdbox-v1"
          install -Dm755 containerd-shim-nerdbox-gpu-v1 "$out/libexec/containerd-shim-nerdbox-gpu-v1"
          install -Dm755 mkfs.erofs "$out/libexec/mkfs.erofs"
          install -Dm755 libsailor.so "$out/libexec/lib/libsailor.so"
          install -Dm644 nerdbox-kernel-* nerdbox-rootfs-*.erofs -t "$out/libexec"
          install -Dm644 apparmor-profile "$out/share/docker-sbx/apparmor-profile"
          install -Dm644 LICENSE THIRD-PARTY-NOTICES -t "$out/share/licenses/docker-sbx"

          wrapProgram "$out/bin/sbx" \
            --prefix PATH : ${lib.makeBinPath [pkgs.e2fsprogs]}

          runHook postInstall
        '';

        meta = {
          description = "Docker Sandboxes CLI";
          homepage = "https://docs.docker.com/ai/sandboxes/";
          license = lib.licenses.unfreeRedistributable;
          mainProgram = "sbx";
          platforms = ["x86_64-linux"];
        };
      };
    };
}
