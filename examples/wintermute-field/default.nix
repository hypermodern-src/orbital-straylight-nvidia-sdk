# wintermute-field — the animated wallpaper field as a CUDA kernel.
#
# The ono-sendai/maas two-axis field (nixos-config wallpaper.frag) ported to
# one __host__ __device__ function: `--verify` renders CPU vs GPU and diffs
# per channel (pixel conformance, the parity-gate doctrine), `--bench`
# reports Mpix/s on the resident GPU. Reads wintermute's theme.json.
#
# GB10 (DGX Spark) is compute capability 12.1.
{
  lib,
  stdenv,
  cmake,
  cuda,
  cudaArch ? if stdenv.hostPlatform.isAarch64 then "sm_121" else "sm_120",
}:
stdenv.mkDerivation {
  pname = "wintermute-field";
  version = "0.1.0";

  src = ./.;

  nativeBuildInputs = [ cmake ];
  buildInputs = [ cuda ];

  cmakeFlags = [
    "-DCUDA_TOOLKIT_ROOT_DIR=${cuda}"
    "-DCMAKE_CUDA_COMPILER=${cuda}/bin/nvcc"
    "-DCMAKE_CUDA_ARCHITECTURES=${lib.removePrefix "sm_" cudaArch}"
  ];

  meta = {
    description = "The wintermute wallpaper field as a CUDA kernel (bench + CPU/GPU conformance)";
    platforms = [
      "aarch64-linux"
      "x86_64-linux"
    ];
  };
}
