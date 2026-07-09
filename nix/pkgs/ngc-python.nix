# ngc-python.nix — Python 3.12 environment from NGC container wheels
#
# Extracts all Python packages from the NGC Triton+TRT-LLM container
# and creates a complete, self-consistent Python environment.
#
# This avoids nixpkgs' torch/CUDA which would rebuild NCCL, magma, etc.

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
  # System libs needed by NGC wheels
  zlib,
  openssl,
  libffi,
  ncurses,
  readline,
  bzip2,
  xz,
  libxml2,
  curl,
  numactl,
  rdma-core,
  ucx,
  libpng,
  zeromq,
}:

let
  python = python312;

  # PyCUDA - build from source since no wheels available

  # Extract all Python packages from NGC container
  ngcPythonPackages = stdenv.mkDerivation {
    pname = "ngc-python-packages";
    version = containerSrc.name or "ngc";

    src = containerSrc;

    nativeBuildInputs = [
      autoPatchelfHook
      findutils
    ];

    buildInputs = [
      stdenv.cc.cc.lib
      zlib
      openssl
      libffi
      ncurses
      readline
      bzip2
      xz
      libxml2
      curl
      numactl
      rdma-core # libibverbs
      ucx # libucp, libuct, libucs
      zeromq # libzmq
      nvidia-sdk
      python # libpython3.12.so
    ];

    autoPatchelfIgnoreMissingDeps = [
      # Driver libs (provided at runtime via /run/opengl-driver/lib)
      "libcuda.so*"
      "libnvidia-ml.so*"
      "libnvidia-*.so*"
      # CUDA libs (from nvidia-sdk, linked at runtime)
      "libcudart.so*"
      "libcublas.so*"
      "libcublasLt.so*"
      "libcudnn.so*"
      "libcufft.so*"
      "libcurand.so*"
      "libcusolver.so*"
      "libcusparse.so*"
      "libcusparseLt.so*"
      "libnccl.so*"
      "libnvinfer.so*"
      "libnvrtc.so*"
      # "libcupti.so.*" # Provided by nvidia-sdk
      # MPI/HPC libs (from container, optional HPC features)
      "libmpi.so*"
      "libmpi_cxx.so*"
      "libopen-pal.so*"
      "libopen-rte.so*"
      "libpmix.so*"
      "libucc.so*"
      "libhcoll.so*"
      "liboshmem.so*"
      "libmca_*.so*"
      # NVSHMEM (from container)
      "libnvshmem*.so*"
      # NVPL (ARM performance libs, from container)
      "libnvpl_lapack_lp64_gomp.so*"
      "libnvpl_blas_lp64_gomp.so*"
      # Tritonserver (from tritonserver package, loaded at runtime)
      "libtritonserver.so*"
      # GDRCopy (optional, for GPU direct)
      "libgdrapi.so*"
      # Mellanox/EFA (optional networking)
      "libmlx5.so*"
      "libefa.so*"
      # LLVM (bundled in container, optional for JIT)
      "libLLVM.so*"
      "libLLVM-*.so*"
      # Triton frontend dependencies (optional)
      "libb64.so*"
      # CUTLASS/MLIR (JIT compilation support)
      "libmlir_cuda_runtime.so*"
      # Intel OneAPI/SYCL libs (not needed for NVIDIA GPUs)
      "libsycl.so*"
      "libze_loader.so*"
      "libimf.so*"
      "libsvml.so*"
      "libirng.so*"
      "libintlc.so*"
      # OpenMP target offload (Intel-specific, not needed for CUDA)
      "libomptarget*.so*"
      # Old libffi version (we provide libffi.so.8)
      "libffi.so.6*"
      # Hardware locality (TBB binding, optional)
      "libhwloc.so*"
      # TBB binding (optional threading optimization)
      "libtbbbind*.so*"
    ];

    dontUnpack = true;
    dontConfigure = true;
    dontBuild = true;

    installPhase = ''
      runHook preInstall

      mkdir -p $out/lib/python3.12/site-packages
      mkdir -p $out/lib
      mkdir -p $out/bin

      # Copy python binary from container
      # Skipped - using nixpkgs python


      # Copy from all Python package locations in the container
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

      # Copy container system libs needed by torch/tensorrt_llm
      echo "Copying container system libraries..."

      # Define all potential library directories
      libdirs=(
        "$src/usr/lib/aarch64-linux-gnu"
        "$src/usr/lib/x86_64-linux-gnu"
        "$src/usr/local/lib"
        "$src/opt/hpcx/ompi/lib"
        "$src/opt/hpcx/ucc/lib"
        "$src/opt/hpcx/ucx/lib"
        "$src/opt/nvidia/nvpl/lib"
        "$src/usr/local/nvshmem/lib"
        "$src/usr/local/cuda/lib64"
        "$src/usr/local/cuda/extras/CUPTI/lib64"
        "$src/usr/lib/llvm-18/lib"
        # NGC 26.06 moved Python packages into a venv; torch/tensorrt_llm ship
        # their own CUDA-linked .so's under the venv site-packages.
        "$src/opt/venv-tritonserver/lib/python3.12/site-packages/torch/lib"
        "$src/opt/venv-tritonserver/lib/python3.12/site-packages/tensorrt_llm/libs"
      )

      for libdir in "''${libdirs[@]}"; do
        if [ -d "$libdir" ]; then
          echo "  from $libdir"
          # Copy all .so files (including symlinks), excluding core system libs
          find "$libdir" -maxdepth 1 -name "*.so*" \
            -not -name "libc.so*" \
            -not -name "libstdc++.so*" \
            -not -name "libm.so*" \
            -not -name "libpthread.so*" \
            -not -name "libdl.so*" \
            -not -name "librt.so*" \
            -not -name "libgcc_s.so*" \
            -not -name "ld-linux*.so*" \
            -not -name "libpython*.so*" \
            -not -name "libresolv.so*" \
            -not -name "libutil.so*" \
            -not -name "libssl.so*" \
            -not -name "libcrypto.so*" \
            -not -name "libreadline.so*" \
            -not -name "libhistory.so*" \
            -not -name "libncurses*.so*" \
            -not -name "libtinfo.so*" \
            -exec cp -an {} $out/lib/ \; 2>/dev/null || true
        fi
      done

      # Copy tensorrt_llm libs
      if [ -d "$src/opt/tensorrt_llm/lib" ]; then
        echo "Copying tensorrt_llm libs..."
        find "$src/opt/tensorrt_llm/lib" -name "*.so*" -exec cp -an {} $out/lib/ \; 2>/dev/null || true
      fi

      # Explicitly find and copy libcusparseLt (needed by torch)
      find $src -name "libcusparseLt.so*" -type f 2>/dev/null | while read -r f; do
        echo "Copying libcusparseLt from $f"
        cp -an "$f" $out/lib/
        base=$(basename "$f")
        # Ensure symlinks exist
        ( cd $out/lib; ln -sf "$base" libcusparseLt.so.0 || true; ln -sf "$base" libcusparseLt.so || true )
      done

      # Explicitly find and copy libnvshmem (needed by torch/NCCL)
      find $src -name "libnvshmem*.so*" -type f 2>/dev/null | while read -r f; do
        echo "Copying libnvshmem from $f"
        cp -an "$f" $out/lib/
        base=$(basename "$f")
        case "$base" in
          libnvshmem_host*.so*)
            ( cd $out/lib; ln -sf "$base" libnvshmem_host.so.3 || true; ln -sf "$base" libnvshmem_host.so || true )
            ;;
        esac
      done

      # Copy OpenMPI from container (avoid nixpkgs rebuild with CUDA)
      # Need full OMPI installation including share files for help texts
      echo "Copying OpenMPI from container..."
      mkdir -p $out/ompi
      if [ -d "$src/opt/hpcx/ompi" ]; then
        cp -an "$src/opt/hpcx/ompi"/* $out/ompi/ 2>/dev/null || true
        # Symlink libs into main lib dir
        find "$out/ompi/lib" -name "*.so*" -exec ln -sf {} $out/lib/ \; 2>/dev/null || true
      fi
      # Create standard symlinks for libmpi
      if [ -f "$out/lib/libmpi.so.40" ] || ls $out/lib/libmpi.so.40* >/dev/null 2>&1; then
        ( cd $out/lib; 
          for f in libmpi.so.40.*; do
            [ -f "$f" ] && ln -sf "$f" libmpi.so.40 || true
          done
          ln -sf libmpi.so.40 libmpi.so || true
        )
      fi

      # Fix permissions
      chmod -R u+w $out || true

      # Remove broken symlinks (e.g. from LLVM where we didn't copy everything)
      find $out/lib -xtype l -delete

      runHook postInstall
    '';

    # Add lib search paths for autoPatchelf
    preFixup = ''
      addAutoPatchelfSearchPath ${nvidia-sdk}/lib64
      addAutoPatchelfSearchPath ${nvidia-sdk}/lib
      addAutoPatchelfSearchPath $out/lib
      addAutoPatchelfSearchPath ${python}/lib
    '';

    # Structural gate: extracted rootfs is a self-contained vendor closure.
    postFixup = modern.verify-closure {
      out = "$out";
      outIsBundle = true;
      systemFloor = [
        "${nvidia-sdk}/lib64"
        "${nvidia-sdk}/lib"
        "${python}/lib"
        "${stdenv.cc.cc.lib}/lib" # libstdc++.so.6 / libgcc_s.so.1
        "${openssl.out}/lib" # libcrypto.so.3 / libssl.so.3
        "${ncurses}/lib" # libtinfo.so.6
        "${zeromq}/lib" # libzmq.so.5 (TRT-LLM UCX wrapper)
        "${libpng.out}/lib" # libpng16.so.16 (torchvision image codec)
      ];
      ignore = [
        "libcuda.so.1"
        "libnvidia-ml.so.1"
        "libnvidia-*.so*"
        # Mellanox HCOLL collective offload — optional, host-provided when present
        # (same rationale as the autoPatchelfIgnoreMissingDeps entry above).
        "libhcoll.so*"
        # Bundled LLVM 18 (clang/LTO/gold plugin); optional JIT path, matches the
        # autoPatchelf ignore. Only the bundled clang toolchain needs it.
        "libLLVM.so*"
        # Intel oneAPI/SYCL libs — not needed for NVIDIA GPUs, matches autoPatchelf ignore
        "libsycl.so*"
        "libze_loader.so*"
        "libimf.so*"
        "libsvml.so*"
        "libirng.so*"
        "libintlc.so*"
        # OpenMP target offload runtime — Intel-specific, not needed for CUDA
        "libomptarget*.so*"
        # Old libffi version (we provide libffi.so.8)
        "libffi.so.6*"
        # Hardware locality (TBB binding, optional)
        "libhwloc.so*"
        # TBB binding (optional threading optimization)
        "libtbbbind*.so*"
      ];
    };

    meta = {
      description = "Python packages extracted from NGC container";
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

    # Symlink tensorrt_llm libs if present
    if [ -d "${ngcPythonPackages}/lib" ]; then
      for f in ${ngcPythonPackages}/lib/*.so*; do
        [ -f "$f" ] && ln -sf "$f" $out/lib/ || true
      done
    fi

    # Create wrapped python (using nixpkgs python)
    # OPAL_PREFIX points OMPI to its data files
    # CUDA_HOME is needed by tensorrt_llm deep_gemm JIT compilation
    # TRITON_LIBCUDA_PATH tells Triton where libcuda.so is (avoids /sbin/ldconfig)
    makeWrapper ${python}/bin/python3 $out/bin/python3 \
      --prefix PYTHONPATH : "$out/lib/python3.12/site-packages" \
      --prefix LD_LIBRARY_PATH : "${python}/lib:${ngcPythonPackages}/lib:$out/lib/python3.12/site-packages/torch/lib:$out/lib/python3.12/site-packages/tensorrt_llm/libs:${nvidia-sdk}/lib64:${nvidia-sdk}/lib:/run/opengl-driver/lib" \
      --set OPAL_PREFIX "${ngcPythonPackages}/ompi" \
      --set CUDA_HOME "${nvidia-sdk}" \
      --set TRITON_LIBCUDA_PATH "/run/opengl-driver/lib"

    ln -s python3 $out/bin/python
    ln -s python3 $out/bin/python3.12

    # Also provide pip (using the same python)
    makeWrapper ${python}/bin/python3 $out/bin/pip \
      --add-flags "-m pip" \
      --prefix PYTHONPATH : "$out/lib/python3.12/site-packages" \
      --prefix LD_LIBRARY_PATH : "${python}/lib:${ngcPythonPackages}/lib:$out/lib/python3.12/site-packages/torch/lib:$out/lib/python3.12/site-packages/tensorrt_llm/libs:${nvidia-sdk}/lib64:${nvidia-sdk}/lib:/run/opengl-driver/lib"

    # Create wrappers for tensorrt_llm CLI tools from entry_points.txt
    # trtllm-bench = tensorrt_llm.commands.bench:main
    # trtllm-build = tensorrt_llm.commands.build:main
    # trtllm-eval = tensorrt_llm.commands.eval:main
    # trtllm-prune = tensorrt_llm.commands.prune:main
    # trtllm-refit = tensorrt_llm.commands.refit:main
    # trtllm-serve = tensorrt_llm.commands.serve:main
    for cmd in bench build eval prune refit serve; do
      makeWrapper $out/bin/python3 $out/bin/trtllm-$cmd \
        --add-flags "-c 'from tensorrt_llm.commands.$cmd import main; main()'"
    done

    # Also wrap torchrun for distributed training
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
    # NGC container extraction includes proprietary components (TensorRT-LLM, cuDNN, etc.)
    license = lib.licenses.unfree;
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    mainProgram = "python3";
  };
}
