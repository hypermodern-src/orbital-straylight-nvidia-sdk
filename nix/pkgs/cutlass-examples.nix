{
  lib,
  devStdenv,
  llvmPackages_20, # Using patched llvmPackages_20 with sm_120 support
  gcc15,
  cmake,
  ninja,
  python3,
  cuda,
  cutlass,
  versions,
}:

devStdenv.mkDerivation {
  pname = "cutlass-examples";
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

  # Tell Clang to use gcc15's libstdc++ for C++23 support with CUDA 13.0
  NIX_CFLAGS_COMPILE = "--gcc-toolchain=${gcc15}";

  cmakeFlags = [
    "-DCUTLASS_NVCC_ARCHS=120" # Blackwell (sm_120)
    "-DCUTLASS_ENABLE_EXAMPLES=ON"
    "-DCUTLASS_ENABLE_TESTS=OFF"
    "-DCUTLASS_ENABLE_PROFILER=OFF"
    "-DCUDA_TOOLKIT_ROOT_DIR=${cuda}"
    "-DCMAKE_CUDA_COMPILER=${cuda}/bin/nvcc" # nvcc generates sm_120 device code
    "-DCMAKE_CUDA_HOST_COMPILER=${llvmPackages_20.clang}/bin/clang++" # Clang for host with sm_120 support
    "-DCMAKE_CUDA_ARCHITECTURES=120"
    "-DCMAKE_CXX_STANDARD=23"
    "-DCMAKE_CUDA_STANDARD=23"
    "-DCMAKE_BUILD_TYPE=RelWithDebInfo"
    "-DCMAKE_CXX_FLAGS=-I${cutlass}/include"
  ];

  postPatch = ''
    # Set Python3 for scripts
    patchShebangs .
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin

    # Find and copy all example binaries
    find examples -type f -executable -exec cp {} $out/bin/ \; 2>/dev/null || true

    # Ensure we got some examples
    if [ -z "$(ls -A $out/bin 2>/dev/null)" ]; then
      echo "Warning: No example binaries found"
    fi

    runHook postInstall
  '';

  meta = {
    description = "CUTLASS ${version} examples";
    homepage = "https://github.com/NVIDIA/cutlass";
    license = lib.licenses.bsd3;
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
}
