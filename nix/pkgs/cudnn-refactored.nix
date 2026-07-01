# nix/pkgs/cudnn-refactored.nix — cuDNN using mkNvidiaPackage
#
# Refactored to use the unified package builder.

{
  lib,
  stdenv,
  zlib,
  nvidiaLib,
  versions,
  cuda,
}:

let
  system = stdenv.hostPlatform.system;
  srcInfo = versions.cudnn.${system} or (throw "cudnn: unsupported system ${system}");

  # Build using unified package builder
  pkgDef = nvidiaLib.mkNvidiaPackage {
    pname = "cudnn";
    version = versions.cudnn.version;

    tarball = {
      inherit (srcInfo) urls;
      inherit (srcInfo) hash;
    };

    runtimeInputs = [
      stdenv.cc.cc.lib
      cuda
      zlib
    ];

    installScript = ''
      tar xf $src
      cd cudnn-linux-*
      cp -r lib include $out/
      ln -sf lib $out/lib64
    '';

    meta = {
      description = "NVIDIA cuDNN ${versions.cudnn.version} - Deep neural network primitives";
      homepage = "https://developer.nvidia.com/cudnn";
      license = lib.licenses.unfree;
      platforms = [
        "x86_64-linux"
        "aarch64-linux"
      ];
    };
  };

in
nvidiaLib.buildPackage {
  inherit stdenv;
  modern = null; # Will be provided by caller
  inherit pkgDef;
}
