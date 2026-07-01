{
  resholve,
  bash,
  coreutils,
  patchelf,
  file,
  findutils,
  gnugrep,
}:
resholve.mkDerivation {
  pname = "patch-nvidia-elfs";
  version = "1.0.0";

  src = ./.;

  installPhase = ''
    mkdir -p $out/bin
    cp patch-nvidia-elfs.sh $out/bin/patch-nvidia-elfs
    chmod +x $out/bin/patch-nvidia-elfs
  '';

  solutions.default = {
    scripts = [ "bin/patch-nvidia-elfs" ];
    interpreter = "${bash}/bin/bash";
    inputs = [
      coreutils
      patchelf
      file
      findutils
      gnugrep
    ];
    execer = [
      "cannot:${patchelf}/bin/patchelf"
      "cannot:${file}/bin/file"
    ];
  };
}
