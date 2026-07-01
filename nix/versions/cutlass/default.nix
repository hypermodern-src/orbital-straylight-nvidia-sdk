# nix/versions/cutlass/default.nix — CUTLASS Versions
#
# NVIDIA CUTLASS CUDA Templates for Linear Algebra Subroutines and Solvers.

_:

{
  cutlass = {
    version = "4.3.3";
    url = "https://github.com/NVIDIA/cutlass/archive/refs/tags/v4.3.3.zip";
    hash = "sha256-uOfSEjbwn/edHEgBikC9wAarn6c6T71ebPg74rv2qlw=";
  };
}
