# Flexible CUTLASS examples builder
# Usage: mkCutlassExamples { exampleTargets = ["00_basic_gemm" "cute_tutorial"]; }
#        mkCutlassExamples { }  # builds all examples

{
  lib,
  devStdenv,
  llvmPackages_git, # LLVM HEAD with native SM120 support
  gcc15,
  glibc,
  cmake,
  ninja,
  python3,
  autoAddDriverRunpath,
  cuda-merged, # Symlink-joined CUDA for C++20/23 support
  cutlass,
  versions,
}:

{
  # Optional: specific example targets to build (e.g., ["00_basic_gemm", "cute_tutorial"])
  # If null or empty, builds all examples
  exampleTargets ? null,
  # Optional: custom name for the package
  pname ?
    if exampleTargets != null then
      "cutlass-examples-${lib.concatStringsSep "-" exampleTargets}"
    else
      "cutlass-examples",
}:

devStdenv.mkDerivation {
  inherit pname;
  version = versions.cutlass.version;

  inherit (cutlass) src;

  nativeBuildInputs = [
    cmake
    ninja
    python3
    autoAddDriverRunpath
  ];

  buildInputs = [
    cuda-merged
    cutlass
    gcc15
    glibc.dev # Required for system headers (features.h, etc.)
  ];

  # Use gcc15's libstdc++
  NIX_CFLAGS_COMPILE = "--gcc-toolchain=${gcc15}";

  preConfigure = ''
    # Set CUDA compiler flags that will be picked up by CMake
    # Replicate the include paths from manual compilation that worked
    # Use gcc15.cc to get the actual GCC (not the wrapper)
    GCC_VERSION=$(basename ${gcc15.cc}/include/c++/*)
    export CUDAFLAGS="--cuda-path=${cuda-merged} --cuda-gpu-arch=sm_120 -I${gcc15.cc}/include/c++/$GCC_VERSION -I${gcc15.cc}/include/c++/$GCC_VERSION/x86_64-unknown-linux-gnu -I${glibc.dev}/include -D__CUDACC_VER_MAJOR__=13 -D__CUDACC_VER_MINOR__=8 -D__CUDA_ARCH__=1200 -DCUDART_VERSION=13000"
    export CUDACXX="${llvmPackages_git.clang}/bin/clang++"
  '';

  cmakeFlags = [
    "-DCUTLASS_NVCC_ARCHS=120" # Blackwell (sm_120)
    "-DCUTLASS_ENABLE_EXAMPLES=ON"
    "-DCUTLASS_ENABLE_TESTS=OFF"
    "-DCUTLASS_ENABLE_PROFILER=OFF"
    "-DCUDA_TOOLKIT_ROOT_DIR=${cuda-merged}"
    "-DCMAKE_CUDA_COMPILER=${llvmPackages_git.clang}/bin/clang++" # Clang from git HEAD as CUDA compiler
    "-DCMAKE_CUDA_COMPILER_ID=Clang"
    "-DCMAKE_CUDA_ARCHITECTURES=120"
    "-DCMAKE_CXX_STANDARD=23" # C++23 support confirmed working with LLVM HEAD
    "-DCMAKE_CUDA_STANDARD=23"
    "-DCMAKE_BUILD_TYPE=RelWithDebInfo"
    "-DCMAKE_CXX_FLAGS=-I${cutlass}/include -D__CUDACC_VER_MAJOR__=13 -D__CUDACC_VER_MINOR__=8 -DCUDART_VERSION=13000"
  ];

  postPatch = ''
    # Set Python3 for scripts
    patchShebangs .

    # Force CUDART_VERSION in all example sources
    find examples -name "*.cu" -o -name "*.cpp" | while read f; do
      sed -i '1i#ifndef CUDART_VERSION\n#define CUDART_VERSION 13000\n#endif' "$f"
    done
  '';

  # Only build specific targets if requested
  ninjaFlags = lib.optionals (exampleTargets != null) exampleTargets;

  dontUseCmakeBuildDir = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin

    ${
      if exampleTargets != null then
        ''
          # Copy specific example binaries from where ninja puts them
          for target in ${lib.concatStringsSep " " exampleTargets}; do
            find . -type f -executable -name "$target" -exec cp {} $out/bin/ \;
          done
        ''
      else
        ''
          # Find and copy all example binaries
          find . -type f -executable \( -name "*blackwell*" -o -name "*fp4*" \) -exec cp {} $out/bin/ \;
        ''
    }

    # Verify we got binaries
    if [ ! -z "$(ls -A $out/bin 2>/dev/null)" ]; then
      echo "Installed examples:"
      ls -1 $out/bin
    fi

    runHook postInstall
  '';

  meta = {
    description = "CUTLASS ${versions.cutlass.version} examples${
      if exampleTargets != null then " (${lib.concatStringsSep ", " exampleTargets})" else ""
    }";

    homepage = "https://github.com/NVIDIA/cutlass";
    license = lib.licenses.bsd3;

    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
}
