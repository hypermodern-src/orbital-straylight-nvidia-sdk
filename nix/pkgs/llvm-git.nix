# Build LLVM/Clang from git HEAD with CUDA 13.0 and SM120 support
{
  lib,
  stdenv,
  cmake,
  ninja,
  python3,
  libxml2,
  zlib,
  ncurses,
  libffi,
  llvm-project-src,
}:

stdenv.mkDerivation {
  pname = "llvm-git";
  version = "git";

  src = llvm-project-src;

  sourceRoot = "source/llvm";

  nativeBuildInputs = [
    cmake
    ninja
    python3
  ];

  buildInputs = [
    libxml2
    zlib
    ncurses
    libffi
  ];

  cmakeFlags = [
    "-DLLVM_ENABLE_PROJECTS=clang;clang-tools-extra"
    "-DCMAKE_BUILD_TYPE=Release"
    "-DLLVM_TARGETS_TO_BUILD=X86;NVPTX;AArch64"
    "-DLLVM_ENABLE_ASSERTIONS=OFF"
    "-DLLVM_INSTALL_UTILS=ON"
    "-DLLVM_BUILD_TOOLS=ON"
    "-DLLVM_INCLUDE_TESTS=OFF"
    "-DLLVM_INCLUDE_EXAMPLES=OFF"
    "-DLLVM_INCLUDE_DOCS=OFF"
    # Skip compiler-rt for now to get past i386 issues
    # Can add later if needed - CUDA doesn't require it
  ];

  # LLVM is huge, enable parallel building
  enableParallelBuilding = true;

  meta = {
    description = "LLVM HEAD with CUDA 13.0 and SM120 support";
    homepage = "https://llvm.org";
    license = lib.licenses.ncsa;
    platforms = lib.platforms.linux;
  };
}
