# The SDK

## One file of versions

`nix/versions.nix` pins the whole surface: the CUDA toolkit (per-arch
installers with SRI hashes), cuDNN, NCCL, TensorRT, cuTensor, CUTLASS,
the NGC container tags, and — critically — the NVIDIA driver version that
matches the toolkit. Nothing else in the tree states a version; every
package is `callPackage`'d against this record
(`nix/modules/default.nix`), so "which CUDA are we on" has exactly one
answer and a bump is one diff.

The driver is *pinned to the toolkit*, not floated: a toolkit that is
newer than the kernel driver fails at runtime in ways that look like
application bugs, so the pairing is a reviewed decision in the same file.

## The packages

`nix/modules/default.nix` assembles the components into flake outputs:
`cuda` (the merged toolkit — with the `lib64 → lib` normalization
applied at the join), `cudnn`, `nccl`, `tensorrt`, `cutensor`,
`cutlass`, the `nvidia-sdk` facade, the NGC-extracted python
environments (TRT-LLM and vLLM variants), and validation targets
(`validate-sdk`, `cuda-samples`, `nccl-tests`). A version-consistency
check reads the toolkit's own `version.json` and fails the build if it
disagrees with `versions.nix` — the file cannot drift from the content.

An LLVM pinned for SM120 (Blackwell) support rides as an input; the
toolkit's `version.json` is also what lets a consuming clang detect the
CUDA installation (a fact the cell projection preserves — see [the nv
cell](./cell.md)).

## The machine side

The repo doubles as the ops story for GPU hosts: `nixosModules.nvidia-sdk`
exposes `hardware.nvidia-sdk.*` (driver selection, `nvidia-persistenced`
for headless boxes, CDI container runtime for Docker/Podman GPU access,
monitoring), and the flake apps wrap the operational tools —
`tritonserver`, the `trtllm-*` family, `torchrun`, the `ncu`/`nsys`
profilers, `nvtop`. None of this enters the cell; it is what runs on the
machines the cell's outputs eventually execute on.
