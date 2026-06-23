{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  versions,
  cuda,
}:

stdenv.mkDerivation {
  pname = "nccl";
  version = versions.nccl.version;

  src = fetchurl {
    # Live NVIDIA upstream redistributable (CUDA 13 .txz).
    url = versions.nccl.${stdenv.hostPlatform.system}.urls.upstream;
    hash = versions.nccl.${stdenv.hostPlatform.system}.hash;
  };

  nativeBuildInputs = [ autoPatchelfHook ];
  buildInputs = [
    stdenv.cc.cc.lib
    cuda
  ];

  # The redist .txz unpacks to a single top-level nccl_<ver>+cuda13.0_<arch>/
  # directory; let the unpacker cd into it so lib/include are at the root.
  setSourceRoot = "sourceRoot=$(echo nccl_*)";
  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out
    cp -a lib include $out/
    ln -sf lib $out/lib64

    # Create unversioned symlink for linker
    ln -sf libnccl.so.2 $out/lib/libnccl.so

    mkdir -p $out/lib/pkgconfig
    cat > $out/lib/pkgconfig/nccl.pc << EOF
    prefix=$out
    libdir=\''${prefix}/lib
    includedir=\''${prefix}/include

    Name: NCCL
    Description: NVIDIA Collective Communication Library
    Version: ${versions.nccl.version}
    Libs: -L\''${libdir} -lnccl
    Cflags: -I\''${includedir}
    EOF

    runHook postInstall
  '';

  passthru.version = versions.nccl.version;

  meta = {
    description = "NVIDIA NCCL ${versions.nccl.version}";
    homepage = "https://developer.nvidia.com/nccl";
    license = lib.licenses.bsd3;
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
}
