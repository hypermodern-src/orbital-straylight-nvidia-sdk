{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
  versions,
  cuda,
  pkgs,
}:

stdenv.mkDerivation {
  pname = "cutlass";
  version = versions.cutlass.version;

  src = fetchFromGitHub {
    owner = "NVIDIA";
    repo = "cutlass";
    rev = "v${versions.cutlass.version}";
    hash = versions.cutlass.hash;
  };

  nativeBuildInputs = [
    cmake
    pkgs.python3
  ];
  buildInputs = [ cuda ];

  cmakeFlags = [
    "-DCUTLASS_ENABLE_HEADERS_ONLY=ON"
    "-DCUTLASS_ENABLE_TESTS=OFF"
    "-DCUTLASS_ENABLE_EXAMPLES=OFF"
  ];

  postPatch = ''
    sed -i 's/enable_language(CUDA)/# enable_language(CUDA)/' CUDA.cmake
    sed -i '/find_package(CUDAToolkit REQUIRED)/a set(CMAKE_CUDA_COMPILER_ID "NVIDIA")\nset(CUDA_VERSION "13.0")' CUDA.cmake

    # Patch arch/config.h to enable SM100+ features with Clang and for SM120 (Blackwell supports Hopper instructions)
    sed -i 's/#if !CUTLASS_CLANG_CUDA && (/#if (/' include/cutlass/arch/config.h

    # Replace CUDACC version checks with always-true (nvcc defines these, Clang doesn't)
    sed -i 's/__CUDACC_VER_MAJOR__ > 12/(1)/' include/cutlass/arch/config.h
    sed -i 's/__CUDACC_VER_MAJOR__ == 12/(1)/' include/cutlass/arch/config.h

    # Enable SM100/101/103/110/121 features for SM120 (Blackwell supports all Hopper instructions)
    sed -i 's/__CUDA_ARCH__ == 1000/__CUDA_ARCH__ == 1000 || __CUDA_ARCH__ == 1200/' include/cutlass/arch/config.h
    sed -i 's/__CUDA_ARCH__ == 1010/__CUDA_ARCH__ == 1010 || __CUDA_ARCH__ == 1200/' include/cutlass/arch/config.h
    sed -i 's/__CUDA_ARCH__ == 1030/__CUDA_ARCH__ == 1030 || __CUDA_ARCH__ == 1200/' include/cutlass/arch/config.h
    sed -i 's/__CUDA_ARCH__ == 1100/__CUDA_ARCH__ == 1100 || __CUDA_ARCH__ == 1200/' include/cutlass/arch/config.h
    sed -i 's/__CUDA_ARCH__ == 1210/__CUDA_ARCH__ == 1210 || __CUDA_ARCH__ == 1200/' include/cutlass/arch/config.h
  '';

  meta = {
    description = "NVIDIA CUTLASS ${versions.cutlass.version} - CUDA Templates for Linear Algebra";
    homepage = "https://github.com/NVIDIA/cutlass";
    license = lib.licenses.bsd3;
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
}
