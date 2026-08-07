# nix/lib/ignore-lists.nix — Shared autoPatchelf/verify-closure ignore patterns
#
# These libraries are intentionally not bundled and are expected to be:
# - Provided by the NVIDIA driver at runtime (libcuda, libnvidia-*)
# - Provided by the system (glibc extensions)
# - Unavailable but optional (Intel oneAPI/SYCL, RDMA transports)
#
# Centralizing these lists ensures consistency across tritonserver, ngc-python,
# and other NGC-extracted packages.

let
  # Driver libraries — always provided by the host NVIDIA driver
  driverLibs = [
    "libcuda.so*"
    "libcuda.so.1"
    "libnvidia-ml.so*"
    "libnvidia-ml.so.1"
    "libnvidia-*.so*"
  ];

  # Intel oneAPI/SYCL — not in NGC container, not needed for NVIDIA GPUs
  intelOneAPI = [
    "libsycl.so*"
    "libze_loader.so*"
    "libimf.so*"
    "libsvml.so*"
    "libirng.so*"
    "libintlc.so*"
    "libomptarget*.so*"
  ];

  # SONAME mismatches between container and nixpkgs
  sonameMismatches = [
    "libffi.so.6*"
    "libhwloc.so.5*"
    "libhwloc.so*"
    "libpng16.so*"
    "libtbbbind*.so*"
  ];

  # Optional transports (UCX/RDMA) — not required for basic operation
  optionalTransports = [
    "libxpmem.so*"
    "libibmad.so*"
  ];

  # NVIDIA proprietary (nsight telemetry, etc.)
  nvidiaProprietary = [
    "libAppLib.so*"
    "libAppLibInterfaces.so*"
  ];

  # Qt6 from nsight — not bundled
  qt6 = [ "libQt6*.so*" ];

  # CUDA version mismatches (nsight ships CUDA 12, SDK has 13)
  cudaVersionMismatch = [ "libcudart.so.12*" ];

  # Python shared lib (provided by nixpkgs)
  pythonLib = [ "libpython312.so*" ];

  # glibc extensions (optional)
  glibcExtensions = [ "libmvec.so.1" ];

  # OpenMP runtime — use toolchain's libgomp, not container's
  # (avoids verify-closure ABI-shadow warnings for numba/omppool)
  openmpRuntime = [ "libgomp.so*" ];

  # OpenCV ffmpeg libs — bundled with opencv-python, not needed if not using video
  opencvFfmpeg = [
    "libavcodec*.so*"
    "libavformat*.so*"
    "libavutil*.so*"
    "libswscale*.so*"
  ];

  # NVSHMEM — optional distributed memory library
  nvshmem = [ "libnvshmem*.so*" ];

  # DPDK/DOCA networking — optional high-performance networking
  dpdkDoca = [
    "librte_*.so*"
    "libdoca_*.so*"
  ];

  # LLVM — bundled with some NGC packages but not always present
  llvm = [
    "libLLVM*.so*"
    "libLTO*.so*"
    "LLVMgold.so*"
  ];

in
{
  # Export individual lists for selective use
  inherit
    driverLibs
    intelOneAPI
    sonameMismatches
    optionalTransports
    nvidiaProprietary
    qt6
    cudaVersionMismatch
    pythonLib
    glibcExtensions
    openmpRuntime
    opencvFfmpeg
    nvshmem
    dpdkDoca
    llvm
    ;

  # Combined list for NGC container packages
  ngcContainerIgnore =
    driverLibs
    ++ intelOneAPI
    ++ sonameMismatches
    ++ optionalTransports
    ++ nvidiaProprietary
    ++ qt6
    ++ cudaVersionMismatch
    ++ pythonLib
    ++ glibcExtensions
    ++ openmpRuntime
    ++ opencvFfmpeg
    ++ nvshmem
    ++ dpdkDoca
    ++ llvm;
}
