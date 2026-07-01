{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
  cuda,
  cudnn,
  tensorrt,
  nccl,
  python3,
}:

let
  version = "10.14";
in
stdenv.mkDerivation {
  pname = "tensorrt-samples";
  inherit version;

  src = fetchFromGitHub {
    owner = "NVIDIA";
    repo = "TensorRT";
    rev = "v${version}";
    hash = "sha256-pWvXpXiUriLDYHqro3HWAmO/9wbGznyUrc9qxq/t0/U=";
  };

  sourceRoot = "source/samples";

  postUnpack = ''
    cp -r source/cmake source/samples/cmake
  '';

  postPatch = ''
    # Patch CMakeLists.txt to add cmake_minimum_required and module path with CUDA support
    sed -i '1 i cmake_minimum_required(VERSION 3.18)\nproject(TensorRTSamples LANGUAGES CXX CUDA)\nenable_language(CUDA)' CMakeLists.txt
    sed -i '21 a list(APPEND CMAKE_MODULE_PATH "''${CMAKE_CURRENT_LIST_DIR}/cmake/modules")' CMakeLists.txt

    # Patch CMakeSamplesTemplate.txt to include required modules and set defaults
    sed -i '17 a list(APPEND CMAKE_MODULE_PATH "''${CMAKE_CURRENT_SOURCE_DIR}/cmake/modules")\ninclude(set_ifndef)\ninclude(find_library_create_target)\nset_ifndef(TRT_OUT_DIR ".")\nset_ifndef(TRT_DEBUG_POSTFIX "")' CMakeSamplesTemplate.txt

    # Remove the hardcoded ONNX_INCLUDE_DIR that points to non-existent parsers/onnx
    sed -i '/set(ONNX_INCLUDE_DIR.*parsers\/onnx/d' CMakeSamplesTemplate.txt
    sed -i '/message(ONNX_INCLUDE_DIR)/d' CMakeSamplesTemplate.txt

    # Comment out DEBUG_POSTFIX line which is causing issues
    sed -i 's/set_target_properties.*DEBUG_POSTFIX.*/#&/' CMakeSamplesTemplate.txt
  '';

  nativeBuildInputs = [
    cmake
    python3
  ];

  buildInputs = [
    cuda
    cudnn
    tensorrt
    nccl
  ];

  cmakeFlags = [
    "-DTRT_LIB_DIR=${tensorrt}/lib"
    "-DCUDA_TOOLKIT_ROOT_DIR=${cuda}"
    "-DONNX_INCLUDE_DIR=${tensorrt}/include"
    "-DCUDA_ROOT=${cuda}"
    "-DCMAKE_EXE_LINKER_FLAGS=-L${cuda}/lib"
    "-DCMAKE_CUDA_ARCHITECTURES=120" # Blackwell (sm_120)
  ];

  NIX_LDFLAGS = "-L${tensorrt}/lib -lcudart -lnvinfer -lnvonnxparser -lnvinfer_plugin";

  installPhase = ''
    mkdir -p $out/bin
    find . -type f -executable -exec cp {} $out/bin/ \;
  '';

  meta = {
    description = "NVIDIA TensorRT Samples ${version}";
    homepage = "https://github.com/NVIDIA/TensorRT";
    license = lib.licenses.asl20;
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
}
