{
  lib,
  stdenv,
  fetchurl,
  zlib,
  extract,
  versions,
  cuda,
  cudnn,
  nccl,
}:

let
  system = stdenv.hostPlatform.system;
  src-info = versions.tensorrt.${system} or (throw "tensorrt: unsupported system ${system}");
in
extract.extract {
  pname = "tensorrt";
  version = versions.tensorrt.version;

  src = fetchurl {
    # Live NVIDIA upstream redistributable.
    url = src-info.urls.upstream;
    inherit (src-info) hash;
  };

  runtime-inputs = [
    stdenv.cc.cc.lib
    cuda
    cudnn
    nccl
    zlib
  ];

  install = ''
    tar xf $src
    cd TensorRT-*
    cp -r lib include bin $out/
    ln -sf lib $out/lib64

    [ -d python ] && cp -r python $out/ || true
  '';

  meta = {
    description = "NVIDIA TensorRT ${versions.tensorrt.version}";
    homepage = "https://developer.nvidia.com/tensorrt";
    license = lib.licenses.unfree;

    platforms = [
      "aarch64-linux"
      "x86_64-linux"
    ];
  };
}
