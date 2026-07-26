# wintermute-field — the animated wallpaper field as a CUDA kernel, plus the
# wayland presenter daemon.
#
# CLI (`wintermute-field`): --cpu / --bench / --verify (CPU-vs-GPU pixel
# conformance) / --theme; renders PPM frames.
#
# Daemon (`wintermute-field-daemon`): wlr-layer-shell background surface
# whose wl_shm pool is cudaHostRegister'd — the kernel writes frames
# DIRECTLY into the compositor's memory (zero-copy on GB10's coherent
# unified memory; memcpy fallback elsewhere). Watches wintermute's
# theme.json live; generation bumps fire the reconcile sweep.
#
# GB10 (DGX Spark) is compute capability 12.1. cudaErrorInsufficientDriver
# on NixOS almost always means libcuda resolved to the toolkit STUB, not a
# real version problem — autoAddDriverRunpath (below) is the cure.
{
  lib,
  stdenv,
  cmake,
  pkg-config,
  autoAddDriverRunpath,
  wayland,
  wayland-scanner,
  wayland-protocols,
  wlr-protocols,
  cuda,
  cudaArch ? if stdenv.hostPlatform.isAarch64 then "sm_121" else "sm_120",
}:
stdenv.mkDerivation {
  pname = "wintermute-field";
  version = "0.2.0";

  src = ./.;

  nativeBuildInputs = [
    cmake
    pkg-config
    wayland-scanner
    # bakes /run/opengl-driver/lib into RUNPATH — without it the runtime
    # dlopens the toolkit's STUB libcuda and reports the driver as
    # insufficient (three days were lost to this mirage; see README)
    autoAddDriverRunpath
  ];
  buildInputs = [
    cuda
    wayland
  ];

  cmakeFlags = [
    "-DCUDA_TOOLKIT_ROOT_DIR=${cuda}"
    "-DCMAKE_CUDA_COMPILER=${cuda}/bin/nvcc"
    "-DCMAKE_CUDA_ARCHITECTURES=${lib.removePrefix "sm_" cudaArch}"
    "-DWLR_LAYER_SHELL_XML=${wlr-protocols}/share/wlr-protocols/unstable/wlr-layer-shell-unstable-v1.xml"
    "-DXDG_SHELL_XML=${wayland-protocols}/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml"
  ];

  meta = {
    description = "The wintermute wallpaper field as a CUDA kernel — CLI (bench/verify) + zero-copy wayland presenter";
    platforms = [
      "aarch64-linux"
      "x86_64-linux"
    ];
  };
}
