# libtorch.nix — C++ libtorch extracted from NGC Python torch
#
# Provides libtorch-bin compatible package for aarch64-linux using
# NGC container's torch which has CUDA support for ARM64.
#
# This enables hasktorch on aarch64-linux with GPU acceleration.
#
{
  lib,
  stdenv,
  python, # NGC python with torch from nvidia-sdk overlay
}:

let
  sitePackages = "lib/python3.12/site-packages/torch";
in
stdenv.mkDerivation {
  pname = "libtorch-bin";
  version = python.version or "2.5.0";

  dontUnpack = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/{lib,include,share}

    # Link libraries from torch
    if [ -d "${python}/${sitePackages}/lib" ]; then
      ln -s ${python}/${sitePackages}/lib/* $out/lib/ 2>/dev/null || true
    fi

    # Also link .so files from the torch root (some torch builds put them there)
    for so in ${python}/${sitePackages}/*.so*; do
      [ -e "$so" ] && ln -sf "$so" $out/lib/
    done

    # Link includes
    if [ -d "${python}/${sitePackages}/include" ]; then
      ln -s ${python}/${sitePackages}/include/* $out/include/
    fi

    # Link cmake files
    if [ -d "${python}/${sitePackages}/share/cmake" ]; then
      ln -s ${python}/${sitePackages}/share/cmake $out/share/cmake
    fi

    # Create pkg-config file
    mkdir -p $out/lib/pkgconfig
    cat > $out/lib/pkgconfig/libtorch.pc << EOF
    prefix=$out
    libdir=\''${prefix}/lib
    includedir=\''${prefix}/include

    Name: libtorch
    Description: PyTorch C++ API (extracted from NGC container)
    Version: $version
    Libs: -L\''${libdir} -ltorch -ltorch_cpu -lc10
    Cflags: -I\''${includedir}
    EOF

    runHook postInstall
  '';

  meta = {
    description = "PyTorch C++ API (libtorch) from NGC container";
    homepage = "https://pytorch.org/";
    license = lib.licenses.bsd3;
    platforms = [
      "aarch64-linux"
      "x86_64-linux"
    ];
  };
}
