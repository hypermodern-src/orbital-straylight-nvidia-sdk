# tritonserver.nix — NGC Triton Inference Server with TensorRT-LLM + vLLM
#
# Extracts all binaries and system libraries from the canonical NGC
# containers into a single self-contained $out/lib, then patches every
# ELF to resolve against that bundle. This eliminates the "which nixpkgs
# lib vs which container lib?" class of ABI-skew bugs entirely.
#
# Merges TRT-LLM container (primary) with vLLM container to provide:
#   - tensorrtllm backend
#   - vllm backend
#   - python backend

{
  lib,
  stdenv,
  addDriverRunpath,
  autoPatchelfHook,
  modern,
  file,
  findutils,
  gnugrep,
  patchelf,
  makeWrapper,
  python312,
  containerSrc,
  vllmContainerSrc,
  versions,
  nvidia-sdk,
  zeromq,
  # Default to TRT-LLM (the full package)
  ...
}:

let
  python = python312;
  version = versions.triton-trtllm-container.version;
  ignoreLists = import ../lib/ignore-lists.nix;

in
stdenv.mkDerivation {
  pname = "tritonserver";
  inherit version;
  src = containerSrc;

  nativeBuildInputs = [
    addDriverRunpath
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
  autoPatchelfIgnoreMissingDeps = ignoreLists.ngcContainerIgnore;

  # Disable automatic autoPatchelf hook - we call it manually in postFixup
  # so we can run addDriverRunpath AFTER it
  dontAutoPatchelf = true;

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

    # ── vLLM backend from vLLM container ────────────────────────────
    if [ -d ${vllmContainerSrc}/opt/tritonserver/backends/vllm ]; then
      echo "Merging vLLM backend from vLLM container..."
      cp -a ${vllmContainerSrc}/opt/tritonserver/backends/vllm $out/backends/
      chmod -R u+w $out/backends/vllm
    fi

    # ── vLLM libs from vLLM container (no-clobber to preserve TRT-LLM versions) ──
    echo "Merging vLLM container libraries..."
    find ${vllmContainerSrc} -name "*.so*" \( -type f -o -type l \) \
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
    # Run autoPatchelf manually (we disabled the hook to control ordering)
    autoPatchelf "$out"

    # Add /run/opengl-driver/lib to RUNPATH for driver libs (libcuda.so, libnvidia-ml.so)
    # Must run AFTER autoPatchelf to avoid being overwritten
    echo "Adding driver runpath to ELF files..."
    while IFS= read -r -d "" f; do
      addDriverRunpath "$f" 2>/dev/null || true
    done < <(find "$out" -type f \( -name '*.so*' -o -executable \) -print0)

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
      ignore = ignoreLists.ngcContainerIgnore;
    }}

    # Wrap binaries
    for exe in $out/bin/*; do
      [ -f "$exe" ] && [ -x "$exe" ] || continue
      wrapProgram "$exe" \
        --set TRITON_SERVER_ROOT "$out" \
        --prefix PYTHONPATH : "$out/python" \
        --add-flags "--backend-directory=$out/backends"
    done
  '';

  passthru = {
    pythonPath = "$out/python";
  };

  meta = {
    description = "NVIDIA Triton Inference Server with TensorRT-LLM + vLLM ${version}";
    homepage = "https://developer.nvidia.com/nvidia-triton-inference-server";
    license = lib.licenses.unfree;
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    mainProgram = "tritonserver";
  };
}
