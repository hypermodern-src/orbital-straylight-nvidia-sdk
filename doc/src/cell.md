# The nv cell

The `nv` cell — the CUDA toolkit as a content-addressed, floor-loaded §12 tree — is produced in
**straylight-toolchain**, from this repo's `cuda` package. The seam is a flake input pinned by rev
(`straylight-toolchain/flake.nix:45`), and the projection is
`straylight-toolchain/nix/flake/toolchain.nix:1051-1119`. This chapter documents the decisions in
that projection, because they are decisions *about this SDK*.

## The prune

The full toolkit bundles the Nsight profilers, whose ELFs `DT_NEEDED` libraries outside any closure
the finalizer could resolve — and none of them are needed to *compile*. Since clang is the CUDA
compiler, the cell keeps only the device-codegen path clang spawns (`cudaMin`,
`toolchain.nix:1062-1093`):

- `bin/`: `ptxas`, `nvlink`, `cicc`, `cudafe++`, `bin2c`, `fatbinary` (+ `.fatbinary-real`),
  `nvdisasm`, `cuobjdump`, `nvprune`, `cu++filt`, `__nvcc_device_query`;
- `nvvm/` (libdevice) and `targets/` (headers + cudart);
- `version.json` — kept because clang detects a CUDA installation by reading it ("cannot find CUDA
  installation" without it);
- `include` and `lib64` as symlinks into `targets/` — and deliberately **no `lib`**, because that
  name belongs to the floor loader's `/lib`;
- CCCL (`libcu++`/thrust/cub) flattened from `include/cccl/` up into the include root, because
  clang's `--cuda-path` adds `<cuda>/include` but not the CCCL subdirectory.

## The stage

`cicc` and `cudafe++` need `libstdc++.so.6` and `libgcc_s.so.1`, which the pruned tree no longer
provides; the projection stages the sovereign C++ runtime from the cxx-glibc sysroot cell into the
finalize search path (`toolchain.nix:1085-1093`), so the manifest resolves from content the producer
controls.

## Finalize and de-shell

The pruned tree goes through the same `mkSelfContained` as rustc/GHC/ Lean: `PT_INTERP` → floor
loader, `DT_NEEDED` closure → `cas/`, Hole-F scrub. One toolkit-specific de-shell: `fatbinary` ships
as a `/bin/sh` shim over `.fatbinary-real`, and the scrub kills its shebang — but clang's invocation
(`--image3=`) is a pure pass-through case, so the cell replaces the shim with a symlink straight at
the real ELF (`toolchain.nix:1104-1112`), the same treatment lean and ghc wrappers got.

## Releasing

From the producer's side the nv cell is just another row: `straylight cell release nv --registry …`
builds this projection, gates it, pushes it, verifies the read-back, and locks the digest into the
toolchain repo's `cells/BUCK` — the toolchain book's CLI chapter is the reference. Bumping CUDA is
therefore: bump `versions.nix` here, bump the input rev in straylight-toolchain, release, and every
consumer follows the digest.
