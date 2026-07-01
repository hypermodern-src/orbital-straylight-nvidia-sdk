# NVIDIA SDK — Project TODO

All items from the codebase review have been addressed.

## Completed

### P0 — Correctness / CI

- [x] **Fix `nix flake check --all-systems`** — replaced `builtins.pathExists` eval-time store probe
  in `nsight-gui-apps.nix` with build-time `[ -f ... ]` check.
- [x] **Pick single versions system** — consolidated on flat `nix/versions.nix`. Updated
  `tests/unit/default.nix`, `docs/generate.nix`, and `tests/default.nix` to use it.
- [x] **Fix unit tests** — rewrote to import flat versions, use `nix/lib/validators.nix` +
  `schemas.nix` directly, fixed missing `lib` binding, removed references to nonexistent test
  directories.
- [x] **Fix SM architecture for aarch64 SBSA** — changed `sm_90a` (Hopper) to `sm_100` (GB200
  Blackwell DC). Added `sm_121` (GB12) to SM table. Fixed in `flake.nix`, `nix/lib/platform.nix`.

### P1 — Module / Docs Consistency

- [x] **Repair `tests/module-check.sh`** — updated path to `nix/modules/nvidia-sdk.nix`, fixed usage
  string.
- [x] **Rewrite `tests/nixos-module-test.nix`** — correct module path, correct
  `hardware.nvidia-sdk.*` API, proper mock options for all NixOS interfaces the module touches.
- [x] **Reconcile README/examples with module options** — updated README, DOCS.md, NIXOS-MODULE.md,
  all 3 example configs. Replaced all stale option names (`cudaVersion`, `expose`, `wrapPrograms`,
  `openKernelModule`, `nvidiaPersistenced`, `opengl.enable`, `powerManagement.enable`,
  `libmodern-nvidia-sdk`) with actual API (`driver.package`, `driver.open`, `systemPackages`,
  `monitoring`, `persistenced`, `container.enable`, `nvidia-sdk`).

### P2 — Maintainability / Refactoring

- [x] **Deduplicate flake/overlay logic** — extracted `nix/lib/platform.nix` with shared `gccPaths`,
  `cudaArch`, `targetTriple`, and `mkCudaStdenv`. Both `perSystem` and `overlays.default` now call
  the shared helper.
- [x] **Harden ELF patching dependencies** — added explicit `findutils` and `gnugrep` to
  `nativeBuildInputs` in `modern.nix` (extract builder), `cuda.nix`, `tritonserver.nix`, and
  `ngc-python.nix`.

### P3 — Security / Supply Chain

- [x] **Document trust boundaries** — added "Trust & Reproducibility" section to README with a table
  of what's trusted and how to disable the binary cache.

### P4 — Contributor Workflow

- [x] **Contributor validation commands** — added "Validation" subsection to README with
  `nix flake check --no-build --all-systems` and other commands. Added update tooling docs.

## Future Considerations

- Wire `nix/versions/default.nix` (validated directory system) into the build path, or remove it to
  reduce confusion.
- Consider adding `nix flake check` (with builds) to CI once GPU runners are available.
- The `driver` section in `versions.nix` still has placeholder hashes (`sha256-AAAA...`). Fill these
  in when pinning a specific driver version.
