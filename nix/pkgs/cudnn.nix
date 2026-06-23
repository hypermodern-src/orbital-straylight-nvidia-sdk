{
  lib,
  stdenv,
  fetchurl,
  zlib,
  extract,
  versions,
  cuda,
}:

let
  system = stdenv.hostPlatform.system;
  src-info = versions.cudnn.${system} or (throw "cudnn: unsupported system ${system}");

in
extract.extract {
  pname = "cudnn";
  version = versions.cudnn.version;

  src = fetchurl {
    # Live NVIDIA upstream redistributable.
    url = src-info.urls.upstream;
    hash = src-info.hash;
  };

  runtime-inputs = [
    stdenv.cc.cc.lib
    cuda
    zlib
  ];

  install = ''
    tar xf $src
    cd cudnn-linux-*
    cp -r lib include $out/
    ln -sf lib $out/lib64
  '';

  meta = {
    description = "NVIDIA cuDNN ${versions.cudnn.version}";
    homepage = "https://developer.nvidia.com/cudnn";
    license = lib.licenses.unfree;
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
}
