{
  lib,
  devStdenv,
  llvmPackages_21,
  gcc15,
  cmake,
  ninja,
  python3,
  cuda,
  cutlass,
  versions,
}:

devStdenv.mkDerivation {
  pname = "cute-examples";
  version = versions.cutlass.version;

  inherit (cutlass) src;

  nativeBuildInputs = [
    cmake
    ninja
    python3
  ];

  buildInputs = [
    cuda
    cutlass
    gcc15
  ];

  CMAKE_CUDA_FLAGS = "--cuda-path=${cuda} -I${cuda}/include -I${cuda}/targets/x86_64-linux/include";

  cmakeFlags = [
    "-DCUTLASS_NVCC_ARCHS=120" # Blackwell (sm_120)
    "-DCUTLASS_ENABLE_EXAMPLES=ON"
    "-DCUTLASS_ENABLE_TESTS=OFF"
    "-DCUDA_TOOLKIT_ROOT_DIR=${cuda}"
    "-DCMAKE_CUDA_COMPILER=${llvmPackages_21.clang}/bin/clang++" # Clang as CUDA compiler (bypasses cudafe++)
    "-DCMAKE_CUDA_COMPILER_ID=Clang"
    "-DCMAKE_CUDA_ARCHITECTURES=120"
    "-DCMAKE_CXX_STANDARD=23"
    "-DCMAKE_CUDA_STANDARD=23"
    "-DCMAKE_BUILD_TYPE=RelWithDebInfo"
  ];

  postPatch = ''
    # Set Python3 for scripts
    patchShebangs .
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin

    # Find and copy all example binaries from build directory
    find examples -type f -executable -exec cp {} $out/bin/ \; 2>/dev/null || true

    # Also check build/examples
    if [ -d build/examples ]; then
      find build/examples -type f -executable -exec cp {} $out/bin/ \; 2>/dev/null || true
    fi

    # List what we found
    echo "Installed examples:"
    ls -la $out/bin/ || echo "No examples found"

    runHook postInstall
  '';

  meta = {
    description = "CuTe (CUTLASS 3.x) examples for Hopper/Blackwell";
    homepage = "https://github.com/NVIDIA/cutlass";
    license = lib.licenses.bsd3;
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
}
