{
  lib,
  stdenv,
  nvidia-sdk,
  nsight-compute ? null,
  nsight-systems ? null,
  versions,
  autoPatchelfHook,
  qt6,
  boost178,
  e2fsprogs,
  gst_all_1,
  nss,
  numactl,
  pulseaudio,
  rdma-core,
  ucx,
  wayland,
  xorg,
}:

let
  qtwayland = lib.getLib qt6.qtwayland;
  qtWaylandPlugins = "${qtwayland}/${qt6.qtbase.qtPluginPrefix}";

  # Nsight tool paths from versions.nix (architecture-specific)
  ncuVersion = versions.nsight.compute.version;
  ncuPath = versions.nsight.compute.${stdenv.hostPlatform.system}.path;
  nsysVersion = versions.nsight.systems.version;
  nsysPath = versions.nsight.systems.${stdenv.hostPlatform.system}.path;
in
stdenv.mkDerivation {
  pname = "nsight-gui-apps";
  inherit (nvidia-sdk) version;

  dontUnpack = true;
  dontStrip = true;

  nativeBuildInputs = [
    autoPatchelfHook
    qt6.wrapQtAppsHook
  ];

  dontWrapQtApps = true;

  buildInputs = [
    qt6.qtbase
    qt6.qtdeclarative
    qt6.qtsvg
    qt6.qtimageformats
    qt6.qtpositioning
    qt6.qtscxml
    qt6.qttools
    qt6.qtwebengine
    qt6.qtwayland
    boost178
    e2fsprogs
    gst_all_1.gst-plugins-base
    gst_all_1.gstreamer
    nss
    numactl
    pulseaudio
    qt6.qtbase
    qtWaylandPlugins
    rdma-core
    ucx
    wayland
    xorg.libX11
    xorg.libXcursor
    xorg.libXdamage
    xorg.libXrandr
    xorg.libXtst
    stdenv.cc.cc.lib
  ];

  autoPatchelfIgnoreMissingDeps = [
    "libcuda.so.1"
    "libnvidia-ml.so.1"
    # NVIDIA bundled proprietary libraries
    "libAppLib.so"
    "libCore.so"
    "libAppLibInterfaces.so"
    "libnvlog.so"
    "libprotobuf-shared.so"
  ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin

    ${lib.optionalString (nsight-compute != null) ''
      # Use nixpkgs nsight-compute as base, copy GUI binary
      if [ -f "${nsight-compute}/bin/${ncuPath}/ncu-ui.bin" ]; then
        cp "${nsight-compute}/bin/${ncuPath}/ncu-ui.bin" $out/bin/
        chmod +w $out/bin/ncu-ui.bin
      fi
    ''}

    ${lib.optionalString (nsight-systems != null) ''
      # Use nixpkgs nsight-systems as base, copy GUI binary
      if [ -f "${nsight-systems}/${nsysPath}/nsys-ui.bin" ]; then
        cp "${nsight-systems}/${nsysPath}/nsys-ui.bin" $out/bin/
        chmod +w $out/bin/nsys-ui.bin
      fi
    ''}

    # Fallback to nvidia-sdk if nixpkgs versions not available
    if [ ! -f "$out/bin/ncu-ui.bin" ]; then
      cp "${nvidia-sdk}/nsight-compute-${ncuVersion}/${ncuPath}/ncu-ui.bin" $out/bin/ || true
      chmod +w $out/bin/ncu-ui.bin 2>/dev/null || true
    fi

    if [ ! -f "$out/bin/nsys-ui.bin" ]; then
      cp "${nvidia-sdk}/nsight-systems-${nsysVersion}/${nsysPath}/nsys-ui.bin" $out/bin/ || true
      chmod +w $out/bin/nsys-ui.bin 2>/dev/null || true
    fi

    runHook postInstall
  '';

  postInstall = ''
    # Wrap the Qt apps with proper library paths
    if [ -f "$out/bin/ncu-ui.bin" ]; then
      ${lib.optionalString (nsight-compute != null) ''
        wrapQtApp "$out/bin/ncu-ui.bin" \
          --prefix LD_LIBRARY_PATH : "${nsight-compute}/bin/${ncuPath}" \
          --prefix QT_PLUGIN_PATH : "${nsight-compute}/bin/${ncuPath}/Plugins"
      ''}
      ${lib.optionalString (nsight-compute == null) ''
        wrapQtApp "$out/bin/ncu-ui.bin" \
          --prefix LD_LIBRARY_PATH : "${nvidia-sdk}/nsight-compute-${ncuVersion}/${ncuPath}" \
          --prefix QT_PLUGIN_PATH : "${nvidia-sdk}/nsight-compute-${ncuVersion}/${ncuPath}/Plugins"
      ''}
      ln -s ncu-ui.bin "$out/bin/ncu-ui"
    fi

    if [ -f "$out/bin/nsys-ui.bin" ]; then
      ${lib.optionalString (nsight-systems != null) ''
        wrapQtApp "$out/bin/nsys-ui.bin" \
          --prefix LD_LIBRARY_PATH : "${nsight-systems}/${nsysPath}" \
          --prefix QT_PLUGIN_PATH : "${nsight-systems}/${nsysPath}/Plugins"
      ''}
      ${lib.optionalString (nsight-systems == null) ''
        wrapQtApp "$out/bin/nsys-ui.bin" \
          --prefix LD_LIBRARY_PATH : "${nvidia-sdk}/nsight-systems-${nsysVersion}/${nsysPath}" \
          --prefix QT_PLUGIN_PATH : "${nvidia-sdk}/nsight-systems-${nsysVersion}/${nsysPath}/Plugins"
      ''}
      ln -s nsys-ui.bin "$out/bin/nsys-ui"
    fi
  '';

  # lib needs libtiff.so.5, but nixpkgs provides libtiff.so.6
  # NOTE: Path checks must be done at build time, not eval time (builtins.pathExists
  # on store paths derived from derivations causes eval failures on foreign systems).
  preFixup = ''
    if [ -f "${nvidia-sdk}/nsight-compute-${ncuVersion}/${ncuPath}/Plugins/imageformats/libqtiff.so" ]; then
      if [ -f "$out/bin/ncu-ui.bin" ]; then
        # Note: This would need to be done on NVIDIA's bundled plugins if they exist
        :
      fi
    fi
  '';

  meta = {
    description = "NVIDIA Nsight GUI profiling tools";
    homepage = "https://developer.nvidia.com/nsight-systems";
    license = lib.licenses.unfree;
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
}
