# ngc-python.nix — Python 3.12 environment from NGC container wheels
#
# Extracts all Python packages and system libraries from the NGC
# Triton+TRT-LLM container into a single self-contained $out/lib,
# then patches every ELF to resolve against that bundle. This
# eliminates the "which nixpkgs lib vs which container lib?" class
# of ABI-skew bugs entirely.

{
  lib,
  stdenv,
  python312,
  autoPatchelfHook,
  findutils,
  containerSrc,
  nvidia-sdk,
  modern,
  makeWrapper,
  zeromq,
}:

let
  python = python312;

  ngcPythonPackages = stdenv.mkDerivation {
    pname = "ngc-python-packages";
    version = containerSrc.name or "ngc";

    src = containerSrc;

    nativeBuildInputs = [
      autoPatchelfHook
      findutils
    ];

    # Only the irreducible floor: glibc, CUDA driver stack, Python, zeromq.
    # Everything else comes from the container's own libs in $out/lib.
    buildInputs = [
      stdenv.cc.cc.lib
      nvidia-sdk
      python
      zeromq
    ];

    # Only driver libs can never be bundled — everything else is in the
    # container and gets dumped to $out/lib.
    autoPatchelfIgnoreMissingDeps = [
      "libcuda.so*"
      "libnvidia-ml.so*"
      "libnvidia-*.so*"
      # Intel oneAPI/SYCL — not in NGC container, not needed for NVIDIA GPUs
      "libsycl.so*"
      "libze_loader.so*"
      "libimf.so*"
      "libsvml.so*"
      "libirng.so*"
      "libintlc.so*"
      "libomptarget*.so*"
      # SONAME mismatch: container has libffi.so.8, libhwloc.so.15
      "libffi.so.6*"
      "libhwloc.so.5*"
      "libhwloc.so*"
      # libpng16 not in container (nixpkgs provides it)
      "libpng16.so*"
      # TBB binding depends on libhwloc
      "libtbbbind*.so*"
      # Optional UCX transports / RDMA
      "libxpmem.so*"
      "libibmad.so*"
      # NVIDIA proprietary (nsight telemetry, not in container)
      "libAppLib.so*"
      "libAppLibInterfaces.so*"
      # Qt6 (from nsight, not in container)
      "libQt6*.so*"
      # CUDA runtime 12 (nsight ships CUDA 12 libs, nvidia-sdk has 13)
      "libcudart.so.12*"
      # Python 3.12 shared lib (nixpkgs provides it, but soname may differ)
      "libpython312.so*"
    ];

    dontUnpack = true;
    dontConfigure = true;
    dontBuild = true;

    installPhase = ''
      runHook preInstall

      mkdir -p $out/lib/python3.12/site-packages
      mkdir -p $out/lib
      mkdir -p $out/bin

      # ── Python packages ──────────────────────────────────────────────
      for pydir in \
        $src/usr/lib/python3/dist-packages \
        $src/usr/lib/python3.12/dist-packages \
        $src/usr/local/lib/python3.12/dist-packages \
        $src/opt/tritonserver/python \
        $src/opt/tensorrt_llm/lib/python3.12/site-packages \
        $src/opt/venv-tritonserver/lib/python3.12/site-packages
      do
        if [ -d "$pydir" ]; then
          echo "Copying Python packages from $pydir"
          cp -an "$pydir"/* $out/lib/python3.12/site-packages/ 2>/dev/null || true
        fi
      done

      # ── Dump every container .so into $out/lib ──────────────────────
      # Excludes: glibc family (can't swap), dynamic linker, libstdc++/libgcc
      # (use Nix toolchain), and libpython (use nixpkgs Python).
      echo "Dumping container libraries to $out/lib ..."
      find $src -name "*.so*" \( -type f -o -type l \) \
        -not -name "libc.so*" \
        -not -name "libm.so*" \
        -not -name "libpthread.so*" \
        -not -name "libdl.so*" \
        -not -name "librt.so*" \
        -not -name "libutil.so*" \
        -not -name "libresolv.so*" \
        -not -name "libnsl.so*" \
        -not -name "ld-linux*.so*" \
        -not -name "libstdc++.so*" \
        -not -name "libgcc_s.so*" \
        -not -name "libpython*.so*" \
        -exec cp -an {} $out/lib/ \; 2>/dev/null || true

      # ── OpenMPI share tree (help texts, etc.) ────────────────────────
      if [ -d "$src/opt/hpcx/ompi" ]; then
        mkdir -p $out/ompi
        cp -an "$src/opt/hpcx/ompi"/* $out/ompi/ 2>/dev/null || true
      fi

      # Purge symlinks that point nowhere (e.g. LLVM partial copies)
      find $out/lib -xtype l -delete

      runHook postInstall
    '';

    preFixup = ''
      addAutoPatchelfSearchPath $out/lib
      addAutoPatchelfSearchPath ${nvidia-sdk}/lib64
      addAutoPatchelfSearchPath ${python}/lib
      addAutoPatchelfSearchPath ${zeromq}/lib
    '';

    postFixup = modern.verify-closure {
      out = "$out";
      outIsBundle = true;
      systemFloor = [
        "${nvidia-sdk}/lib64"
        "${python}/lib"
        "${zeromq}/lib"
        "${stdenv.cc.cc.lib}/lib"
      ];
      ignore = [
        "libcuda.so.1"
        "libnvidia-ml.so.1"
        "libnvidia-*.so*"
        # Intel oneAPI/SYCL — not in NGC container, not needed for NVIDIA GPUs
        "libsycl.so*"
        "libze_loader.so*"
        "libimf.so*"
        "libsvml.so*"
        "libirng.so*"
        "libintlc.so*"
        "libomptarget*.so*"
        # SONAME mismatch: container has libffi.so.8, libhwloc.so.15
        "libffi.so.6*"
        "libhwloc.so.5*"
        "libhwloc.so*"
        # libpng16 not in container (nixpkgs provides it)
        "libpng16.so*"
        # TBB binding depends on libhwloc
        "libtbbbind*.so*"
        # Optional UCX transports / RDMA
        "libxpmem.so*"
        "libibmad.so*"
        # NVIDIA proprietary (nsight telemetry, not in container)
        "libAppLib.so*"
        "libAppLibInterfaces.so*"
        # Qt6 (from nsight, not in container)
        "libQt6*.so*"
        # CUDA runtime 12 (nsight ships CUDA 12 libs, nvidia-sdk has 13)
        "libcudart.so.12*"
        # Python 3.12 shared lib (nixpkgs provides it, but soname may differ)
        "libpython312.so*"
      ];
    };

    meta = {
      description = "Python packages and system libs extracted from NGC container";
      platforms = [
        "x86_64-linux"
        "aarch64-linux"
      ];
    };
  };

in
stdenv.mkDerivation {
  pname = "python3-ngc";
  inherit (python) version;

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;
  dontStrip = true;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin $out/lib

    # Symlink NGC packages
    ln -s ${ngcPythonPackages}/lib/python3.12 $out/lib/python3.12

    # Symlink all container libs
    if [ -d "${ngcPythonPackages}/lib" ]; then
      for f in ${ngcPythonPackages}/lib/*.so*; do
        [ -f "$f" ] && ln -sf "$f" $out/lib/ || true
      done
    fi

    # OPAL_PREFIX points OMPI to its data files
    # CUDA_HOME is needed by tensorrt_llm deep_gemm JIT compilation
    # TRITON_LIBCUDA_PATH tells Triton where libcuda.so is
    makeWrapper ${python}/bin/python3 $out/bin/python3 \
      --prefix PYTHONPATH : "$out/lib/python3.12/site-packages" \
      --prefix LD_LIBRARY_PATH : "${python}/lib:${ngcPythonPackages}/lib:${nvidia-sdk}/lib64:${nvidia-sdk}/lib:/run/opengl-driver/lib" \
      --set OPAL_PREFIX "${ngcPythonPackages}/ompi" \
      --set CUDA_HOME "${nvidia-sdk}" \
      --set TRITON_LIBCUDA_PATH "/run/opengl-driver/lib"

    ln -s python3 $out/bin/python
    ln -s python3 $out/bin/python3.12

    # pip
    makeWrapper ${python}/bin/python3 $out/bin/pip \
      --add-flags "-m pip" \
      --prefix PYTHONPATH : "$out/lib/python3.12/site-packages" \
      --prefix LD_LIBRARY_PATH : "${python}/lib:${ngcPythonPackages}/lib:${nvidia-sdk}/lib64:${nvidia-sdk}/lib:/run/opengl-driver/lib"

    # TRT-LLM CLI tools
    for cmd in bench build eval prune refit serve; do
      makeWrapper $out/bin/python3 $out/bin/trtllm-$cmd \
        --add-flags "-c 'from tensorrt_llm.commands.$cmd import main; main()'"
    done

    # torchrun
    makeWrapper $out/bin/python3 $out/bin/torchrun \
      --add-flags "-m torch.distributed.run"

    runHook postInstall
  '';

  passthru = {
    inherit python ngcPythonPackages;
    inherit (python) pythonVersion;
    sitePackages = "lib/python3.12/site-packages";
  };

  meta = {
    description = "Python ${python.version} with NGC container packages (torch, triton, tensorrt_llm)";
    homepage = "https://catalog.ngc.nvidia.com";
    license = lib.licenses.unfree;
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    mainProgram = "python3";
  };
}
