# NOTE: This package is NOT wired into flake.nix and requires a
# `versions.nsight-dl-designer` entry in nix/versions.nix that does
# not yet exist.  It will fail at eval time if imported as-is.
# Add the version data before enabling.
{
  lib,
  stdenv,
  fetchurl,
  makeWrapper,
  autoPatchelfHook,
  qt6,
  zlib,
  libGL,
  libx11,
  libxcursor,
  libxrandr,
  libxi,
  libxinerama,
  libxext,
  libxxf86vm,
  fontconfig,
  freetype,
  libxcrypt-legacy,
  openssl,
  versions,
}:

let
  # Architecture-specific subdirectory
  archDir =
    if stdenv.hostPlatform.system == "x86_64-linux" then
      "linux-desktop-dl-x64"
    else
      "linux-desktop-dl-sbsa";
in
stdenv.mkDerivation {
  pname = "nsight-dl-designer";
  version = versions.nsight-dl-designer.version;

  src = fetchurl { inherit (versions.nsight-dl-designer.${stdenv.hostPlatform.system}) url hash; };

  nativeBuildInputs = [
    makeWrapper
    autoPatchelfHook
    qt6.wrapQtAppsHook
  ];

  buildInputs = [
    stdenv.cc.cc.lib
    zlib
    libGL
    libx11
    libxcursor
    libxrandr
    libxi
    libxinerama
    libxext
    libxxf86vm
    fontconfig
    freetype
    qt6.qtbase
    qt6.qtwayland
    qt6.qtwebchannel
    qt6.qtwebengine
    qt6.qtpositioning
    libxcrypt-legacy
    openssl
  ];

  autoPatchelfIgnoreMissingDeps = [
    "libcudart.so.13"
    "libcuda.so.1"
    "libnvidia-ml.so.1"
  ];

  dontStrip = true;

  unpackPhase = ''
    runHook preUnpack
    sh $src --noexec --target extracted
    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    cp -r extracted/pkg $out/
    chmod -R u+w $out

    # Create wrapper in bin
    ln -s ../pkg/host/${archDir}/nsight-dl $out/bin/nsight-dl-designer

    runHook postInstall
  '';

  postFixup = ''
    # Wrap with bundled libs (like nsight-systems/compute)
    wrapQtApp $out/pkg/host/${archDir}/nsight-dl.bin \
      --prefix LD_LIBRARY_PATH : "$out/pkg/host/${archDir}" \
      --prefix QT_PLUGIN_PATH : "$out/pkg/host/${archDir}/plugins"
  '';

  meta = {
    description = "NVIDIA Nsight Deep Learning Designer";
    homepage = "https://developer.nvidia.com/nsight-dl-designer";
    license = lib.licenses.unfree;
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
}
