{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  gcc,
  vulkan-loader,
}:
# Upstream's Vulkan build is published per release. Packaging the release
# binary avoids rebuilding ggml-vulkan here; the service only needs the
# server, and upstream has no install rules.
stdenv.mkDerivation (finalAttrs: {
  pname = "parakeet-cpp";
  version = "0.6.1";

  src = fetchurl {
    url = "https://github.com/mudler/parakeet.cpp/releases/download/v${finalAttrs.version}/parakeet-v${finalAttrs.version}-bin-linux-vulkan-x64.tar.gz";
    hash = "sha256-iB/ZnVMaTc/CYRmklprsYbg5C6hOnWQXFkEdTB2y3jo=";
  };

  nativeBuildInputs = [autoPatchelfHook];
  # libgomp and libstdc++ come from gcc.cc.lib; libvulkan is loaded through
  # the NixOS driver path the same way llama.cpp's Vulkan build does.
  buildInputs = [(lib.getLib gcc.cc) vulkan-loader];

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin $out/share/licenses/parakeet-cpp
    install -m755 parakeet-server $out/bin/parakeet-server
    install -m755 parakeet-cli $out/bin/parakeet-cli
    install -m644 LICENSE $out/share/licenses/parakeet-cpp/LICENSE
    runHook postInstall
  '';

  meta = {
    description = "Parakeet.cpp ASR server and CLI (upstream Vulkan build)";
    homepage = "https://github.com/mudler/parakeet.cpp";
    license = lib.licenses.mit;
    mainProgram = "parakeet-server";
    platforms = ["x86_64-linux"];
    sourceProvenance = [lib.sourceTypes.binaryNativeCode];
  };
})
