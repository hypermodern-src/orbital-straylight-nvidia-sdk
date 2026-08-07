# tritonserver.nix — NGC Triton Inference Server with TensorRT-LLM
#
# Extracts all binaries and system libraries from the canonical NGC
# containers into a single self-contained $out/lib, then patches every
# ELF to resolve against that bundle. This eliminates the "which nixpkgs
# lib vs which container lib?" class of ABI-skew bugs entirely.
#
# Optionally merges the vLLM container with the TRT-LLM container to provide:
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
  vllmContainerSrc ? null,
  versions,
  nvidia-sdk,
  openssl,
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
    openssl
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

    mkdir -p $out/{bin,include,backends,python,tensorrt_llm,share/tritonserver/model-repositories}

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

    ${lib.optionalString (vllmContainerSrc != null) ''
      # ── Optional vLLM backend ───────────────────────────────────────
      if [ -d ${vllmContainerSrc}/opt/tritonserver/backends/vllm ]; then
        echo "Merging vLLM backend from vLLM container..."
        cp -a ${vllmContainerSrc}/opt/tritonserver/backends/vllm $out/backends/
        chmod -R u+w $out/backends/vllm
      fi

      # No-clobber preserves the TRT-LLM container's library versions.
      echo "Merging vLLM container libraries..."
      find ${vllmContainerSrc} -name "*.so*" -type f \
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
        -not -name "libcrypto.so*" \
        -not -name "libssl.so*" \
        -exec cp -an {} $out/lib/ \; 2>/dev/null || true
      find ${vllmContainerSrc} -name "*.so*" -type l \
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
        -not -name "libcrypto.so*" \
        -not -name "libssl.so*" \
        -exec cp -an {} $out/lib/ \; 2>/dev/null || true
    ''}

    # ── Dump every container .so into $out/lib (on top of tritonserver's) ──
    # Excludes: glibc family (can't swap), dynamic linker, libstdc++/libgcc
    # (use Nix toolchain), and libpython (use nixpkgs Python).
    echo "Dumping container libraries to $out/lib ..."
    # Copy regular files before symlinks. NGC contains absolute CUDA symlinks
    # with the same basename as a real library elsewhere in the rootfs; copying
    # in filesystem order can install the broken absolute link first and then
    # make `-n` skip the real file (notably libnvshmem_host).
    find $src -name "*.so*" -type f \
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
      -not -name "libcrypto.so*" \
      -not -name "libssl.so*" \
      -exec cp -an {} $out/lib/ \; 2>/dev/null || true
    find $src -name "*.so*" -type l \
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
      -not -name "libcrypto.so*" \
      -not -name "libssl.so*" \
      -exec cp -an {} $out/lib/ \; 2>/dev/null || true

    # ── Python bits ─────────────────────────────────────────────────
    for pydir in \
      $src/usr/lib/python3/dist-packages \
      $src/usr/local/lib/python3.12/dist-packages \
      $src/opt/tritonserver/python \
      $src/opt/venv-tritonserver/lib/python3.12/site-packages
    do
      [ -d "$pydir" ] || continue
      # Container files are read-only. Make an existing namespace writable
      # before merging the next site-packages tree; a globbed `cp -a` would
      # otherwise silently leave partial packages behind on collisions (the
      # Triton frontend's `openai/` directory versus the OpenAI SDK is one).
      chmod -R u+w $out/python
      cp -a "$pydir"/. $out/python/
    done

    # The in-process Python server does not consume TRITON_SERVER_ROOT; its
    # constructor embeds the container's /opt defaults. Relocate every default
    # used for backend, cache, and repository-agent discovery into this output.
    substituteInPlace $out/python/tritonserver/_api/_server.py \
      --replace-fail "/opt/tritonserver" "$out"

    # OpenRouter requires usage in every streamed response. Triton 26.06 only
    # emits the terminal usage chunk when the client explicitly sets
    # stream_options.include_usage, so force it at the packaged provider edge
    # for both chat-completion and completion streaming paths.
    substituteInPlace \
      $out/python/openai/openai_frontend/engine/triton_engine.py \
      --replace-fail \
        "include_usage = request.stream_options and request.stream_options.include_usage" \
        "include_usage = True"

    # Direct-Hugging-Face TensorRT-LLM LLMAPI repository template. This is
    # the PyTorch backend path used by current TRT-LLM; no engine build step.
    if [ -d $src/app/all_models/llmapi ]; then
      cp -a $src/app/all_models/llmapi \
        $out/share/tritonserver/model-repositories/
      chmod -R u+w $out/share/tritonserver/model-repositories/llmapi
    fi

    # ── Generic .so → .so.* symlinks ────────────────────────────────
    if [ -d $out/lib ]; then
      cd $out/lib
      for lib in *.so.*; do
        [ -f "$lib" ] || continue
        base=''${lib%%.so.*}
        [ -e "$base.so" ] || ln -sf "$lib" "$base.so" 2>/dev/null || true
        soname=$(patchelf --print-soname "$lib" 2>/dev/null || true)
        case "$soname" in
          *.so*)
            # Replace an absolute container symlink with a store-local SONAME
            # link when the real versioned ELF has now been copied.
            [ -e "$soname" ] || ln -sf "$lib" "$soname" 2>/dev/null || true
            ;;
        esac
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
    addAutoPatchelfSearchPath ${openssl.out}/lib
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
        "${openssl.out}/lib"
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

    # Triton's in-process OpenAI-compatible frontend starts and owns the
    # server. Keep it as a first-class app instead of asking callers to know
    # an NGC container-internal Python path.
    makeWrapper ${python}/bin/python3 $out/bin/triton-openai \
      --add-flags "$out/python/openai/openai_frontend/main.py" \
      --set TRITON_SERVER_ROOT "$out" \
      --prefix PYTHONPATH : "$out/python:$out/tensorrt_llm" \
      --prefix LD_PRELOAD : "$out/lib/libtritonserver.so"
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
