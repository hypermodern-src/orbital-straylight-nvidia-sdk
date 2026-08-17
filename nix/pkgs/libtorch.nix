# libtorch.nix — C++ libtorch extracted from NGC Python torch
#
# Exposes the vendor torch/{lib,include,share} subtrees without flattening or
# rewriting them.  Their relative topology is part of the libtorch ABI.
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

    mkdir -p $out/share
    test -d "${python}/${sitePackages}/lib"
    test -d "${python}/${sitePackages}/include"
    ln -s "${python}/${sitePackages}/lib" $out/lib
    ln -s "${python}/${sitePackages}/include" $out/include
    if [ -d "${python}/${sitePackages}/share/cmake" ]; then
      ln -s "${python}/${sitePackages}/share/cmake" $out/share/cmake
    fi

    # Create pkg-config file
    mkdir -p $out/share/pkgconfig
    cat > $out/share/pkgconfig/libtorch.pc << EOF
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
