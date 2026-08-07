# ngc-python.nix — Python 3.12 environments from NGC containers
#
# Provides two Python environments:
#   - python-trtllm: TRT-LLM container (torch 2.10, tensorrt_llm)
#   - python-vllm: vLLM container (torch 2.13, vllm) — default
#
# These cannot be merged because they have incompatible torch versions.

{
  lib,
  stdenv,
  addDriverRunpath,
  python312,
  autoPatchelfHook,
  patchelf,
  findutils,
  containerSrc,
  nvidia-sdk,
  modern,
  makeWrapper,
  zeromq,
  openssl,
  # Package variant: "trtllm" or "vllm"
  variant ? "trtllm",
}:

let
  python = python312;
  ignoreLists = import ../lib/ignore-lists.nix;

  # Inner derivation: extract and patch container packages
  ngcPythonPackages = stdenv.mkDerivation {
    pname = "ngc-python-packages-${variant}";
    version = containerSrc.name or "ngc";

    src = containerSrc;

    nativeBuildInputs = [
      addDriverRunpath
      autoPatchelfHook
      patchelf
      findutils
    ];

    # Only the irreducible floor: glibc, CUDA driver stack, Python, zeromq, openssl.
    # Everything else comes from the container's own libs in $out/lib.
    buildInputs = [
      stdenv.cc.cc.lib
      nvidia-sdk
      python
      zeromq
      openssl
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

      mkdir -p $out/lib/python3.12/site-packages
      mkdir -p $out/lib
      mkdir -p $out/bin

      # ── Python packages ──────────────────────────────────────────────
      # Use -n (no-clobber) to avoid overwriting existing files. The order
      # matters: system packages first, then venv (venv may have stubs that
      # we don't want to clobber the real .so files with).
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

      # ── Fix scipy packaging conflict ──────────────────────────────────
      # Some scipy installs have both _propack.cpython-*.so AND _propack/ dir.
      # The .so shadows the dir, breaking imports. Remove conflicting .so files
      # when the directory version exists (directory has the actual modules).
      chmod -R u+w $out/lib/python3.12/site-packages || true
      find $out/lib/python3.12/site-packages/scipy -name "*.cpython-*.so" 2>/dev/null | while read -r so; do
        base="''${so%.cpython-*}"
        if [ -d "$base" ]; then
          echo "Removing conflicting .so that shadows directory: $so"
          rm -f "$so"
        fi
      done

      # ── Fix numpy _core / core module duplication ────────────────────────
      # Container numpy 1.26.4 has both numpy/core/ (main) and numpy/_core/
      # (compat stubs). The _core/ directory has .py files that import from core/,
      # but also has .so files that SHADOW those .py files. When scipy loads
      # numpy._core._multiarray_umath, it gets a different ufunc class than
      # numpy.core._multiarray_umath, breaking isinstance() checks.
      # Fix: Remove .so files from _core/ where .py shims exist.
      echo "Fixing numpy _core/*.so shadowing .py shims..."
      for so in $out/lib/python3.12/site-packages/numpy/_core/*.cpython-*.so; do
        [ -f "$so" ] || continue
        base="''${so%.cpython-*}"
        py="''${base}.py"
        if [ -f "$py" ]; then
          echo "Removing $so (shadowed by $py shim)"
          rm -f "$so"
        fi
      done

      # ── Dump container shared libraries into $out/lib ──────────────────────
      # ONLY copy actual shared libraries (lib*.so*), NOT Python extension modules
      # (*.cpython-*.so). Python extensions must stay in site-packages to avoid
      # LD_LIBRARY_PATH pollution causing version mismatches.
      #
      # Excludes: glibc family (can't swap), dynamic linker, libstdc++/libgcc
      # (use Nix toolchain), libpython (use nixpkgs Python), libcrypto/libssl
      # (use nixpkgs OpenSSL to match Python's _ssl module), and driver libs
      # (libcuda/libnvidia-* must come from /run/opengl-driver/lib at runtime).
      echo "Dumping container libraries to $out/lib ..."
      # Copy regular files first. Copying symlinks and regular files in a single
      # no-clobber pass is traversal-order dependent: a SONAME symlink can win
      # the basename, then become dangling when its versioned target had a
      # different source basename. Rebuild SONAME links from ELF metadata below.
      find $src -name "lib*.so*" -type f \
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
        -not -name "libcuda.so*" \
        -not -name "libnvidia-*.so*" \
        -exec cp -an {} $out/lib/ \; 2>/dev/null || true

      # Python extensions record SONAMEs such as libnvshmem_host.so.3, while
      # NGC may only leave the fully-versioned regular file after extraction.
      # Reconstruct those links deterministically before closure verification.
      for library in $out/lib/lib*.so*; do
        [ -f "$library" ] || continue
        soname=$(patchelf --print-soname "$library" 2>/dev/null || true)
        [ -n "$soname" ] || continue
        if [ ! -e "$out/lib/$soname" ]; then
          ln -s "$(basename "$library")" "$out/lib/$soname"
        fi
      done

      # ── OpenMPI share tree (help texts, etc.) ────────────────────────
      if [ -d "$src/opt/hpcx/ompi" ]; then
        mkdir -p $out/ompi
        cp -an "$src/opt/hpcx/ompi"/* $out/ompi/ 2>/dev/null || true
      fi

      # ── Fix broken symlinks in .libs directories ──────────────────────
      # Python wheels like opencv_python_headless bundle libs in .libs/ dirs.
      # Some are symlinks to container paths (e.g., /opt/ffmpeg-safe-cv2-shim-v8/).
      # These symlinks become broken after extraction. Fix by resolving them
      # to the actual file from the container, dereferencing any symlink chains.
      echo "Fixing broken symlinks in .libs directories..."
      for libsdir in $out/lib/python3.12/site-packages/*.libs; do
        [ -d "$libsdir" ] || continue
        for link in "$libsdir"/*; do
          if [ -L "$link" ] && [ ! -e "$link" ]; then
            # Broken symlink - get the target and resolve it within container
            target=$(readlink "$link")
            container_path="$src$target"
            # Fully resolve the symlink chain to get the actual file
            if [ -e "$container_path" ]; then
              real_file=$(readlink -f "$container_path")
              if [ -f "$real_file" ]; then
                echo "Resolving broken symlink: $link -> $real_file"
                rm "$link"
                cp "$real_file" "$link"
              else
                echo "Warning: Cannot find real file for $link -> $target"
              fi
            else
              echo "Warning: Cannot resolve symlink $link -> $target"
            fi
          fi
        done
      done

      # Purge symlinks that point nowhere (e.g. LLVM partial copies)
      # Exclude *.libs directories - they were already fixed above
      find $out/lib -xtype l -not -path "*.libs/*" -delete

      runHook postInstall
    '';

    preFixup = ''
      addAutoPatchelfSearchPath $out/lib
      addAutoPatchelfSearchPath ${nvidia-sdk}/lib64
      addAutoPatchelfSearchPath ${python}/lib
      addAutoPatchelfSearchPath ${zeromq}/lib

      # Add all .libs directories from Python packages (e.g., opencv_python_headless.libs)
      # These contain bundled shared libraries that extensions link against.
      for libsdir in $out/lib/python3.12/site-packages/*.libs; do
        if [ -d "$libsdir" ]; then
          echo "Adding autoPatchelf search path: $libsdir"
          addAutoPatchelfSearchPath "$libsdir"
        fi
      done
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
    '';

    meta = {
      description = "Python packages and system libs extracted from NGC ${variant} container";
      platforms = [
        "x86_64-linux"
        "aarch64-linux"
      ];
    };
  };

  # CLI tools based on variant
  cliTools =
    if variant == "trtllm" then
      ''
        # TRT-LLM CLI tools
        for cmd in bench build eval prune refit serve; do
          makeWrapper $out/bin/python3 $out/bin/trtllm-$cmd \
            --add-flags "-c 'from tensorrt_llm.commands.$cmd import main; main()'"
        done
      ''
    else
      ''
        # vLLM CLI
        makeWrapper $out/bin/python3 $out/bin/vllm \
          --add-flags "-m vllm.entrypoints.openai.api_server"
      '';

  description =
    if variant == "trtllm" then
      "Python ${python.version} with TensorRT-LLM (torch 2.10)"
    else
      "Python ${python.version} with vLLM (torch 2.13)";

in
stdenv.mkDerivation {
  pname = "python3-ngc-${variant}";
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
    # TRITON_PTXAS_PATH tells Triton where ptxas is (doesn't search PATH)
    # CPATH provides CUDA headers for Triton's runtime JIT compilation (cuda.h)
    # PATH includes nvidia-sdk/bin for other CUDA tools
    # FLASHINFER_DISABLE_VERSION_CHECK: disable version check for flashinfer
    # Note: nvidia_cutlass_dsl.pth points to a nested python_packages dir that
    # needs to be on PYTHONPATH explicitly since we don't process .pth files.
    makeWrapper ${python}/bin/python3 $out/bin/python3 \
      --prefix PYTHONPATH : "$out/lib/python3.12/site-packages:$out/lib/python3.12/site-packages/nvidia_cutlass_dsl/python_packages" \
      --prefix LD_LIBRARY_PATH : "${python}/lib:${ngcPythonPackages}/lib:${nvidia-sdk}/lib64:${nvidia-sdk}/lib:/run/opengl-driver/lib" \
      --prefix CPATH : "${nvidia-sdk}/include" \
      --prefix LIBRARY_PATH : "${nvidia-sdk}/lib64:${nvidia-sdk}/lib:/run/opengl-driver/lib" \
      --prefix PATH : "${nvidia-sdk}/bin" \
      --set OPAL_PREFIX "${ngcPythonPackages}/ompi" \
      --set CUDA_HOME "${nvidia-sdk}" \
      --set TRITON_LIBCUDA_PATH "/run/opengl-driver/lib" \
      --set TRITON_PTXAS_PATH "${nvidia-sdk}/bin/ptxas" \
      --set FLASHINFER_DISABLE_VERSION_CHECK "1"

    ln -s python3 $out/bin/python
    ln -s python3 $out/bin/python3.12

    # pip
    makeWrapper ${python}/bin/python3 $out/bin/pip \
      --add-flags "-m pip" \
      --prefix PYTHONPATH : "$out/lib/python3.12/site-packages:$out/lib/python3.12/site-packages/nvidia_cutlass_dsl/python_packages" \
      --prefix LD_LIBRARY_PATH : "${python}/lib:${ngcPythonPackages}/lib:${nvidia-sdk}/lib64:${nvidia-sdk}/lib:/run/opengl-driver/lib"

    ${cliTools}

    # torchrun (both variants have torch)
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
    inherit description;
    homepage = "https://catalog.ngc.nvidia.com";
    license = lib.licenses.unfree;
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    mainProgram = "python3";
  };
}
