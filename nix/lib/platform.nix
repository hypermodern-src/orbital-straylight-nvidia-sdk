# nix/lib/platform.nix — Shared platform computations
#
# Returns platform-specific values (gccPaths, cudaArch, targetTriple)
# and a mkCudaStdenv builder, used by both the flake perSystem and the overlay.
#
# Usage:
#   platform = import ./nix/lib/platform.nix { inherit lib stdenv gcc15; };
#   cudaStdenv = platform.mkCudaStdenv {
#     inherit (pkgs) wrapCCWith stdenvAdapters glibc;
#     inherit llvm-git cuda-merged;
#     gcc15Stdenv = pkgs.gcc15Stdenv;
#     ccLib = stdenv.cc.cc.lib;
#     gcc15Pkg = pkgs.gcc15;
#   };
{
  lib,
  stdenv,
  gcc15,
}:

let
  isAarch64 = stdenv.hostPlatform.isAarch64;

  targetTriple = if isAarch64 then "aarch64-unknown-linux-gnu" else "x86_64-unknown-linux-gnu";

  gccVersion = lib.versions.majorMinor gcc15.version + ".0";

  gccPaths = {
    include = "${gcc15.cc}/include/c++/${gccVersion}";
    includeArch = "${gcc15.cc}/include/c++/${gccVersion}/${targetTriple}";
    lib = "${gcc15.cc}/lib/gcc/${targetTriple}/${gccVersion}";
  };

  # aarch64 = SBSA data center (GB200 = sm_100, GB12 = sm_121)
  # x86_64  = consumer/workstation Blackwell RTX (sm_120)
  cudaArch = if isAarch64 then "sm_100" else "sm_120";

  # Build the CUDA-aware clang stdenv.
  # Caller passes package-set-specific references.
  mkCudaStdenv =
    {
      wrapCCWith,
      stdenvAdapters,
      glibc,
      llvm-git,
      cuda-merged,
      gcc15Stdenv,
      ccLib, # stdenv.cc.cc.lib
      gcc15Pkg, # pkgs.gcc15 (wrapper)
    }:
    let
      clangGit = wrapCCWith {
        cc = llvm-git;
        useCcForLibs = true;
        gccForLibs = gcc15.cc;
      };

      baseStdenv = stdenvAdapters.overrideCC gcc15Stdenv clangGit;
    in
    stdenvAdapters.addAttrsToDerivation {
      dontStrip = true;
      separateDebugInfo = false;
      hardeningDisable = [ "all" ];
      noAuditTmpdir = true;

      NIX_CFLAGS_COMPILE = lib.concatStringsSep " " [
        "-I${gccPaths.include}"
        "-I${gccPaths.includeArch}"
        "-I${glibc.dev}/include"
        "--cuda-path=${cuda-merged}"
        "--cuda-gpu-arch=${cudaArch}"
        "-B${glibc}/lib"
        "-B${gccPaths.lib}"
        "-U_FORTIFY_SOURCE"
        "-g3"
        "-fno-omit-frame-pointer"
        "-fno-limit-debug-info"
      ];

      NIX_LDFLAGS = lib.concatStringsSep " " [
        "-L${gccPaths.lib}"
        "-L${gcc15Pkg}/lib"
        "-L${ccLib}/lib"
        "-L${glibc}/lib"
        "-L${cuda-merged}/lib64"
        "-lcudart"
      ];

      NIX_CXXSTDLIB_COMPILE = "-std=c++23";
    } baseStdenv;
in
{
  inherit
    isAarch64
    targetTriple
    gccVersion
    gccPaths
    cudaArch
    mkCudaStdenv
    ;
}
