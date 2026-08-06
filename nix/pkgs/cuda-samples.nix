{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
  cuda,
  cudaArch ? if stdenv.hostPlatform.isAarch64 then "sm_100" else "sm_120",
  ...
}:

let
  version = "13.0";
in
stdenv.mkDerivation {
  pname = "cuda-samples";
  inherit version;

  src = fetchFromGitHub {
    owner = "NVIDIA";
    repo = "cuda-samples";
    rev = "v${version}";
    hash = "sha256-bOcAE/OzOI6MWTh+bFZfq1en6Yawu+HI8W+xK+XaCqg=";
  };

  nativeBuildInputs = [ cmake ];
  buildInputs = [ cuda ];

  cmakeFlags = [
    "-DCUDA_TOOLKIT_ROOT_DIR=${cuda}"
    "-DCMAKE_CUDA_COMPILER=${cuda}/bin/nvcc"
    "-DCMAKE_CUDA_ARCHITECTURES=${lib.removePrefix "sm_" cudaArch}"
  ];

  postPatch = ''
        # The samples pass `-lineinfo`, which nvcc forwards to cicc as
        # `-generate-line-info` — a spelling this toolkit's cicc rejects.
        # Line info is debug-tool garnish; strip it.
        find Samples -name CMakeLists.txt -exec sed -i 's/ -lineinfo//g' {} +

        # Build core samples confirmed to exist in v13.0
        cat > CMakeLists.txt << 'EOF'
    cmake_minimum_required(VERSION 3.20)
    project(cuda_samples CUDA CXX)

    find_package(CUDAToolkit REQUIRED)

    # 0_Introduction - Basic CUDA concepts
    add_subdirectory(Samples/0_Introduction/vectorAdd)
    add_subdirectory(Samples/0_Introduction/vectorAddDrv)
    add_subdirectory(Samples/0_Introduction/matrixMul)
    add_subdirectory(Samples/0_Introduction/matrixMulDrv)
    add_subdirectory(Samples/0_Introduction/clock)
    add_subdirectory(Samples/0_Introduction/simpleStreams)
    add_subdirectory(Samples/0_Introduction/simpleMultiGPU)

    # 1_Utilities - Essential diagnostic tools
    add_subdirectory(Samples/1_Utilities/deviceQuery)
    add_subdirectory(Samples/1_Utilities/deviceQueryDrv)

    # 3_CUDA_Features - Tensor Cores
    add_subdirectory(Samples/3_CUDA_Features/cudaTensorCoreGemm)
    add_subdirectory(Samples/3_CUDA_Features/bf16TensorCoreGemm)
    add_subdirectory(Samples/3_CUDA_Features/tf32TensorCoreGemm)

    # 4_CUDA_Libraries - cuBLAS, cuFFT examples
    add_subdirectory(Samples/4_CUDA_Libraries/simpleCUBLAS)
    add_subdirectory(Samples/4_CUDA_Libraries/simpleCUFFT)
    add_subdirectory(Samples/4_CUDA_Libraries/conjugateGradient)

    EOF
  '';

  installPhase = ''
    mkdir -p $out/bin
    find . -type f -executable -exec cp {} $out/bin/ \;
  '';

  meta = {
    description = "NVIDIA CUDA Samples ${version}";
    homepage = "https://github.com/NVIDIA/cuda-samples";
    license = lib.licenses.bsd3;
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
}
