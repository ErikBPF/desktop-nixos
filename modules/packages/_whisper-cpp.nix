{
  lib,
  stdenv,
  cmake,
  ninja,
  fetchFromGitHub,
  shaderc,
  spirv-headers,
  vulkan-headers,
  vulkan-loader,
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "whisper-cpp-vulkan";
  version = "1.9.5";

  src = fetchFromGitHub {
    owner = "ggml-org";
    repo = "whisper.cpp";
    rev = "v${finalAttrs.version}";
    hash = "sha256-Qqqpt+pvCQwSbyaBr1bdb7q+3LbELTcloHdiSikGPc4=";
  };

  nativeBuildInputs = [cmake ninja];
  buildInputs = [shaderc spirv-headers vulkan-headers vulkan-loader];

  cmakeFlags = [
    "-G Ninja"
    "-DGGML_VULKAN=ON"
    "-DBUILD_SHARED_LIBS=OFF"
    "-DGGML_NATIVE=OFF"
    "-DWHISPER_BUILD_EXAMPLES=ON"
    "-DWHISPER_SDL2=OFF"
    "-DCMAKE_BUILD_TYPE=Release"
    "-DVulkan_INCLUDE_DIR=${vulkan-headers}/include"
    "-DVulkan_LIBRARY=${vulkan-loader}/lib/libvulkan.so"
    "-DVulkan_GLSLC_EXECUTABLE=${shaderc}/bin/glslc"
    "-DSPIRV-Headers_DIR=${spirv-headers}/share/cmake/SPIRV-Headers"
    "-DCMAKE_C_FLAGS=-I${spirv-headers}/include"
    "-DCMAKE_CXX_FLAGS=-I${spirv-headers}/include"
  ];

  buildPhase = ''
    runHook preBuild
    cmake --build . --target whisper-server whisper-cli -j''${NIX_BUILD_CORES:-1}
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 bin/whisper-server $out/bin/whisper-server
    install -Dm755 bin/whisper-cli $out/bin/whisper-cli
    install -Dm644 ../LICENSE $out/share/licenses/whisper-cpp/LICENSE
    runHook postInstall
  '';

  meta = {
    description = "whisper.cpp server and CLI with the ggml Vulkan backend";
    homepage = "https://github.com/ggml-org/whisper.cpp";
    license = lib.licenses.mit;
    mainProgram = "whisper-server";
    platforms = ["x86_64-linux"];
  };
})
