{
  cuda,
  cudnn,
  extract,
  fetchurl,
  lib,
  nccl,
  stdenv,
  versions,
  zlib,
}:
let
  system = stdenv.hostPlatform.system;
  src-info = versions.tensorrt-rtx.${system} or (throw "tensorrt-rtx: unsupported system ${system}");
in
extract.extract {
  pname = "tensorrt-rtx";
  version = versions.tensorrt-rtx.version;

  src = fetchurl {
    # Live NVIDIA upstream redistributable.
    url = src-info.urls.upstream;
    hash = src-info.hash;
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
    description = "NVIDIA TensorRT-RTX ${versions.tensorrt.version}";
    homepage = "https://developer.nvidia.com/tensorrt-rtx";
    license = lib.licenses.unfree;

    platforms = [
      "x86_64-linux"
    ];
  };
}
