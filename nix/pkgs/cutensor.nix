{
  lib,
  stdenv,
  fetchurl,
  extract,
  versions,
  cuda,
}:

let
  system = stdenv.hostPlatform.system;
  src-info = versions.cutensor.${system} or (throw "cutensor: unsupported system ${system}");

in
extract.extract {
  pname = "cutensor";
  version = versions.cutensor.version;

  src = fetchurl {
    # Live NVIDIA upstream redistributable.
    url = src-info.urls.upstream;
    inherit (src-info) hash;
  };

  runtime-inputs = [
    stdenv.cc.cc.lib
    cuda
  ];

  install = ''
    tar xf $src
    cd libcutensor-*
    cp -r lib include $out/
    [ -d lib64 ] && cp -r lib64/* $out/lib/ || true
    ln -sf lib $out/lib64
    [ -f LICENSE ] && cp LICENSE $out/ || true
  '';

  meta = {
    description = "NVIDIA cuTENSOR ${versions.cutensor.version}";
    homepage = "https://developer.nvidia.com/cutensor";
    license = lib.licenses.unfree;
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
}
