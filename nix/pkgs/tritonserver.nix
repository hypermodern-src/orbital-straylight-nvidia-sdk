# tritonserver.nix — NGC Triton Inference Server with TensorRT-LLM
#
# Extracts all binaries and system libraries from the canonical NGC
# container into a single self-contained $out/lib, then patches every
# ELF to resolve against that bundle. This eliminates the "which nixpkgs
# lib vs which container lib?" class of ABI-skew bugs entirely.

{
  lib,
  stdenv,
  autoPatchelfHook,
  modern,
  file,
  findutils,
  gnugrep,
  patchelf,
  makeWrapper,
  python312,
  containerSrc,
  versions,
  nvidia-sdk,
  zeromq,
  # Default to TRT-LLM (the full package)
  ...
}:

let
  python = python312;
  version = versions.triton-trtllm-container.version;

in
stdenv.mkDerivation {
  pname = "tritonserver";
  inherit version;
  src = containerSrc;

  nativeBuildInputs = [
    autoPatchelfHook
    file
    findutils
    gnugrep
    patchelf
    makeWrapper
  ];

  # Only the irreducible floor: glibc, CUDA driver stack, Python, zeromq.
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
    # glibc optional math vectorization
    "libmvec.so.1"
  ];

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/{bin,include,backends,python,tensorrt_llm}

    # ── Tritonserver tree (MUST come before lib dump — it creates $out/lib) ──
    if [ -d $src/opt/tritonserver ]; then
      cp -a $src/opt/tritonserver/* $out/
      chmod -R u+w $out
    fi

    [ ! -e $out/lib64 ] && ln -s lib $out/lib64

    # ── TensorRT-LLM ────────────────────────────────────────────────
    if [ -d $src/opt/tensorrt_llm ]; then
      cp -a $src/opt/tensorrt_llm/* $out/tensorrt_llm/
      if [ -d $out/tensorrt_llm/libs ]; then
        cp -a $out/tensorrt_llm/libs/*.so* $out/lib/ 2>/dev/null || true
      fi
      chmod -R u+w $out/tensorrt_llm
    elif [ -d $src/opt/venv-tritonserver/lib/python3.12/site-packages/tensorrt_llm ]; then
      cp -a $src/opt/venv-tritonserver/lib/python3.12/site-packages/tensorrt_llm/* $out/tensorrt_llm/
      if [ -d $out/tensorrt_llm/libs ]; then
        cp -a $out/tensorrt_llm/libs/*.so* $out/lib/ 2>/dev/null || true
      fi
      chmod -R u+w $out/tensorrt_llm
    fi

    # ── Dump every container .so into $out/lib (on top of tritonserver's) ──
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

    # ── Python bits ─────────────────────────────────────────────────
    for pydir in \
      $src/usr/lib/python3/dist-packages \
      $src/usr/local/lib/python3.12/dist-packages \
      $src/opt/tritonserver/python \
      $src/opt/venv-tritonserver/lib/python3.12/site-packages
    do
      [ -d "$pydir" ] && cp -a "$pydir"/* $out/python/ 2>/dev/null || true
    done

    # ── Generic .so → .so.* symlinks ────────────────────────────────
    if [ -d $out/lib ]; then
      cd $out/lib
      for lib in *.so.*; do
        [ -f "$lib" ] || continue
        base=''${lib%%.so.*}
        [ -e "$base.so" ] || ln -sf "$lib" "$base.so" 2>/dev/null || true
      done
    fi

    # Purge broken symlinks
    find $out/lib -xtype l -delete

    chmod -R u+w $out || true

    # Fix python shebangs
    find $out -type f \( -name "*.py" -o -perm -0100 \) | while read -r f; do
      [ -f "$f" ] || continue
      if head -1 "$f" 2>/dev/null | grep -q '^#!.*python'; then
        sed -i "1s|^#!.*python.*|#!${python}/bin/python|" "$f" 2>/dev/null || true
      fi
    done
  '';

  preFixup = ''
    addAutoPatchelfSearchPath $out/lib
    addAutoPatchelfSearchPath ${nvidia-sdk}/lib64
    addAutoPatchelfSearchPath ${python}/lib
    addAutoPatchelfSearchPath ${zeromq}/lib
  '';

  postFixup = ''
    autoPatchelf "$out"

    # Structural gate: self-contained bundle, only driver libs are host-provided.
    ${modern.verify-closure {
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
        # glibc optional math vectorization
        "libmvec.so.1"
      ];
    }}

    # Wrap binaries
    for exe in $out/bin/*; do
      [ -f "$exe" ] && [ -x "$exe" ] || continue
      wrapProgram "$exe" \
        --set TRITON_SERVER_ROOT "$out" \
        --suffix LD_LIBRARY_PATH : "$out/lib:${nvidia-sdk}/lib64:${nvidia-sdk}/lib:/run/opengl-driver/lib" \
        --prefix PYTHONPATH : "$out/python"
    done
  '';

  passthru = {
    pythonPath = "$out/python";
  };

  meta = {
    description = "NVIDIA Triton Inference Server with TensorRT-LLM ${version}";
    homepage = "https://developer.nvidia.com/nvidia-triton-inference-server";
    license = lib.licenses.unfree;
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    mainProgram = "tritonserver";
  };
}
