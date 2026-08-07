# Introduction

This is the spoke book for **straylight-nvidia-sdk**: the repository that carries NVIDIA's
proprietary stack — CUDA toolkit, cuDNN, NCCL, TensorRT, cuTensor, CUTLASS, driver, NGC containers —
as pinned, hash-verified nix packages, plus the NixOS module that runs them on real machines.

In the sovereign build's terms this repo is a **producer's upstream**: it does not project cells
itself. straylight-toolchain consumes its `cuda` package as a flake input and runs the toolkit
through the same §12 finalize → floor-project → OCI pipeline as the compiler trio, producing the
`nv` cell that `nv_binary`/`nv_library` builds stream by digest. The [SDK chapter](./sdk.md) covers
what this repo builds and why the versions are pinned the way they are;
[the nv cell chapter](./cell.md) covers the seam — what survives the prune, what gets staged in, and
how a release propagates.

Two facts shape everything here:

1. **The toolkit and the driver are one decision.** `nix/versions.nix` is the single source of
   truth: toolkit 13.x, the matching driver, and every component hash live in one file, so a CUDA
   bump is one reviewed diff, not a scavenger hunt.
2. **clang is the CUDA compiler.** There is no nvcc in the build path: the cxx cell's clang 22
   compiles `.cu`, and the toolkit contributes only the device-codegen tools clang spawns (`ptxas`,
   `cicc`, `fatbinary`, …) plus headers and `cudart`. That is what makes the aggressive prune in the
   cell projection possible.

This book follows the spoke-book standard (the hub's "The books" page) and is deliberately thin: the
floor machinery is the toolchain book's subject, the `nv_*` rules are the examples tour's, and this
book covers only what lives here.
