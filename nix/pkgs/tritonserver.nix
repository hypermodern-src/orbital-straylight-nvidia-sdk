# tritonserver.nix — NGC Triton Inference Server with TensorRT-LLM
#
# Extracted from the canonical NGC container.
# Includes all backends: TensorRT, TensorRT-LLM, Python, ONNX, etc.

{ lib
, stdenv
, fetchurl
, autoPatchelfHook
, modern
, file
, findutils
, gnugrep
, patchelf
, makeWrapper
, python312
, abseil-cpp
, acl
, audit
, boost
, bzip2
, curl
, cyrus_sasl
, db
, dbus
, e2fsprogs
, expat
, gdbm
, glib
, gnutls
, gperftools
, grpc
, icu
, keyutils
, libarchive
, libbsd
, libcap
, libcap_ng
, libevent
, libffi
, libgcrypt
, libgpg-error
, libkrb5
, libmd
, libselinux
, libsemanage
, libsepol
, libssh
, libuuid
, libxcrypt
, libxml2
, lz4
, ncurses
, nettle
, numactl
, rdma-core
, # libibverbs/libmlx5/librdmacm — RDMA over the ConnectX/QSFP fabric
  ucx
, # libuct/libucp/libucs — UCX transports used by NCCL/TRT-LLM multi-node
  zeromq
, # libzmq — used by the TRT-LLM UCX wrapper
  openldap
, # openmpi - use container's MPI to avoid nixpkgs CUDA dep chain
  openssl
, pam
, pcre
, pcre2
, protobuf
, rapidjson
, re2
, readline
, rtmpdump
, systemd
, containerSrc
, tzdata
, util-linux
, versions
, xz
, zlib
, nvidia-sdk
, # Default to TRT-LLM (the full package)
  ...
}:

let
  python = python312;

  libxml2LegacyVersion = "2.9.14";
  libxml2-legacy = libxml2.overrideAttrs (_: {
    version = libxml2LegacyVersion;
    src = fetchurl {
      url = "https://download.gnome.org/sources/libxml2/${lib.versions.majorMinor libxml2LegacyVersion}/libxml2-${libxml2LegacyVersion}.tar.xz";
      sha256 = "sha256-YNdKJX0czsBHXnScui8hVZ5IE577pv8oIkNXx8eY3+4=";
    };
  });

  runtime-inputs = [
    abseil-cpp
    acl
    audit
    boost
    bzip2
    curl
    cyrus_sasl
    db
    dbus
    e2fsprogs.dev
    expat
    gdbm
    glib
    gnutls
    gperftools
    grpc
    icu
    keyutils
    libarchive
    libbsd
    libcap
    libcap_ng
    libevent
    libffi
    libgcrypt
    libgpg-error
    libkrb5
    libmd
    libselinux
    libsemanage
    libsepol
    libssh
    libuuid
    libxcrypt
    libxml2-legacy
    lz4
    ncurses
    nettle
    numactl
    rdma-core
    ucx
    zeromq
    nvidia-sdk
    openldap
    # openmpi - container has its own, avoid nixpkgs CUDA chain
    openssl
    pam
    pcre
    pcre2
    protobuf
    python
    rapidjson
    re2
    readline
    rtmpdump
    stdenv.cc.cc.lib
    systemd
    tzdata
    util-linux
    xz
    zlib
  ];

  # include containerSrc so its /usr/lib* get onto RPATH as well
  runpath = modern.mk-runpath (runtime-inputs ++ [ containerSrc ]);

  # Wrapper LD_LIBRARY_PATH: only the dirs holding runtime-dlopen'd fabric libs.
  # Must NOT include ${containerSrc}/lib (the container glibc) — LD_LIBRARY_PATH
  # is searched before the loader's own glibc, so a container libc.so.6 there
  # shadows the Nix glibc and crashes startup (__nptl_change_stack_perm,
  # GLIBC_PRIVATE). Ordinary deps are already resolved via ELF RPATH.
  wrapperLibPaths = lib.concatStringsSep ":" (
    [
      "${placeholder "out"}/lib"
      "${placeholder "out"}/tensorrt_llm/lib"
      "${placeholder "out"}/tensorrt_llm/libs"
      "${placeholder "out"}/tensorrt_llm/libs/ucx"
      "${placeholder "out"}/tensorrt_llm/libs/ucx/ucx"
      "${containerSrc}/opt/hpcx/ompi/lib"
      "${containerSrc}/opt/hpcx/ucc/lib"
      "${containerSrc}/opt/hpcx/ucx/lib"
    ]
    # nixpkgs runtime deps (liblzma/zlib/openssl/nvidia-sdk/…). Safe to include
    # because the wrapper APPENDS (--suffix) this list, so the Nix loader's own
    # glibc always resolves first; these only supplement. mk-runpath over
    # runtime-inputs excludes containerSrc, so no container glibc dir is here.
    ++ [ (modern.mk-runpath runtime-inputs) ]
  );

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

  buildInputs = runtime-inputs;

  autoPatchelfIgnoreMissingDeps = [
    "libcuda.so.1"
    "libLLVM.so.18.1"
    "libgc.so.1"
    "libobjc_gc.so.4.0.0"
    "libonig.so.5"
    "libmpfr.so.6"
    "libxxhash.so.0"
    "libjq.so.1.0.4"
    "libcaffe2_nvrtc.so"
    "libsasl2.so.2"
    "libapt-pkg.so.6.0"
    "libapt-private.so.0.0"
  ];

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    mkdir -p $out/{bin,lib,include,backends,python}

    copy_one() {
      local pattern="$1" extra="$2"
      local f
      f=$(find "$src" -name "$pattern" -type f 2>/dev/null | head -1 || true)
      [ -z "$f" ] && return 0
      echo "Copying $pattern from $f"
      cp -a "$f" $out/lib/
      base=$(basename "$f")
      eval "$extra"
    }

    # libcupti — MUST come from the container's CUDA (13.1), not the 13.3
    # toolkit. torch's profiler is built against the container CUPTI's
    # version-symbols; the 13.3 toolkit's libcupti.so.13 satisfies the soname
    # but fails the versioned-symbol check at load. Prefer the real versioned
    # file under the container's cuda-*/targets tree.
    cupti_src=$(find $src/usr/local/cuda-*/targets/*/lib -name "libcupti.so.2*" -type f 2>/dev/null | head -1 || true)
    if [ -n "$cupti_src" ]; then
      echo "Copying container CUPTI from $cupti_src"
      cp -a "$cupti_src" $out/lib/
      ( cd $out/lib;
        b=$(basename "$cupti_src");
        ln -sf "$b" libcupti.so.13 || true
        ln -sf "$b" libcupti.so || true
      )
    else
      copy_one "libcupti.so*" '
        ( cd $out/lib;
          ln -sf "$base" libcupti.so.13 || true
          ln -sf "$base" libcupti.so || true
        )
      '
    fi

    # libb64
    find $src -name "libb64.so*" -type f 2>/dev/null -exec cp -a {} $out/lib/ \;

    # libgdrapi — GPUDirect RDMA (GPU<->NIC fast path over the ConnectX/QSFP
    # fabric). Copy the specific lib out of the container's arch libdir into
    # $out/lib; we must NOT put that whole libdir on the search path because it
    # also contains the container's glibc (see preFixup note).
    find $src -path "*-linux-gnu/libgdrapi.so*" -type f 2>/dev/null -exec cp -a {} $out/lib/ \;
    ( cd $out/lib; for g in libgdrapi.so.*; do
        [ -f "$g" ] || continue
        ln -sf "$g" libgdrapi.so.2 2>/dev/null || true
        ln -sf libgdrapi.so.2 libgdrapi.so 2>/dev/null || true
      done )

    # libdcgm* and libdcgmmoduleconfig*
    find $src -path "*/libdcgm*.so*" -type f 2>/dev/null | while read -r f; do
      echo "Copying DCGM lib from $f"
      cp -a "$f" $out/lib/
      base=$(basename "$f")
      case "$base" in
        libdcgm.so.*)
          ( cd $out/lib; ln -sf "$base" libdcgm.so.4 || true; ln -sf "$base" libdcgm.so || true )
          ;;
        libdcgmmoduleconfig.so.*)
          ( cd $out/lib; ln -sf "$base" libdcgmmoduleconfig.so.4 || true; ln -sf "$base" libdcgmmoduleconfig.so || true )
          ;;
      esac
    done

    # libcusparseLt
    find $src -name "libcusparseLt.so*" -type f 2>/dev/null | while read -r f; do
      echo "Copying libcusparseLt from $f"
      cp -a "$f" $out/lib/
      base=$(basename "$f")
      ( cd $out/lib; ln -sf "$base" libcusparseLt.so.0 || true; ln -sf "$base" libcusparseLt.so || true )
    done

    # libnvshmem*
    find $src -name "libnvshmem*.so*" -type f 2>/dev/null | while read -r f; do
      echo "Copying libnvshmem from $f"
      cp -a "$f" $out/lib/
      base=$(basename "$f")
      case "$base" in
        libnvshmem_host*.so*)
          ( cd $out/lib; ln -sf "$base" libnvshmem_host.so.3 || true; ln -sf "$base" libnvshmem_host.so || true )
          ;;
      esac
    done

    # libcaffe2_nvrtc
    find $src -name "libcaffe2_nvrtc.so*" -type f 2>/dev/null -exec cp -a {} $out/lib/ \;

    # ICU 74 from container
    find $src -name "libicu*.so.74*" -type f 2>/dev/null | while read -r f; do
      echo "Copying ICU lib from $f"
      cp -a "$f" $out/lib/
      base=$(basename "$f")
      libname=''${base%%.so.*}
      ( cd $out/lib;
        ln -sf "$base" "$libname.so.74" || true
        ln -sf "$base" "$libname.so" || true
      )
    done

    # tritonserver tree
    if [ -d $src/opt/tritonserver ]; then
      cp -a $src/opt/tritonserver/* $out/
      chmod -R u+w $out
    fi

    [ -d $out/lib ] && [ ! -e $out/lib64 ] && ln -s lib $out/lib64

    # tensorrt_llm — /opt/tensorrt_llm in <=25.12; moved into the venv
    # site-packages in NGC 26.06 (/opt/venv-tritonserver/.../tensorrt_llm,
    # with the .so's under a libs/ subdir).
    if [ -d $src/opt/tensorrt_llm ]; then
      mkdir -p $out/tensorrt_llm
      cp -a $src/opt/tensorrt_llm/* $out/tensorrt_llm/
      chmod -R u+w $out/tensorrt_llm
    elif [ -d $src/opt/venv-tritonserver/lib/python3.12/site-packages/tensorrt_llm ]; then
      mkdir -p $out/tensorrt_llm/lib
      cp -a $src/opt/venv-tritonserver/lib/python3.12/site-packages/tensorrt_llm/* $out/tensorrt_llm/
      if [ -d $out/tensorrt_llm/libs ]; then
        cp -a $out/tensorrt_llm/libs/*.so* $out/tensorrt_llm/lib/ 2>/dev/null || true
      fi
      chmod -R u+w $out/tensorrt_llm
    fi

    # Python bits
    for pydir in \
      $src/usr/lib/python3/dist-packages \
      $src/usr/local/lib/python3.12/dist-packages \
      $src/opt/tritonserver/python \
      $src/opt/venv-tritonserver/lib/python3.12/site-packages
    do
      [ -d "$pydir" ] && cp -a "$pydir"/* $out/python/ 2>/dev/null || true
    done

    # NCCL from nvidia-sdk (if present)
    if [ -d ${nvidia-sdk}/lib64 ]; then
      for lib in ${nvidia-sdk}/lib64/libnccl*.so*; do
        [ -f "$lib" ] || continue
        ln -sf "$lib" $out/lib/$(basename "$lib") || true
        base=$(basename "$lib")
        case "$base" in
          libnccl.so.[0-9]*.[0-9]*)
            # Link versioned file to .so.2 and .so
            ( cd $out/lib; 
              ln -sf "$base" libnccl.so.2 || true
              ln -sf libnccl.so.2 libnccl.so || true
            )
            ;;
        esac
      done
    fi

    # generic .so → .so.* symlinks
    if [ -d $out/lib ]; then
      cd $out/lib
      for lib in *.so.*; do
        [ -f "$lib" ] || continue
        base=''${lib%%.so.*}
        [ -e "$base.so" ] || ln -sf "$lib" "$base.so" 2>/dev/null || true
      done
    fi

    chmod -R u+w $out || true

    # fix python shebangs
    find $out -type f \( -name "*.py" -o -perm -0100 \) | while read -r f; do
      [ -f "$f" ] || continue
      if head -1 "$f" 2>/dev/null | grep -q '^#!.*python'; then
        sed -i "1s|^#!.*python.*|#!${python}/bin/python|" "$f" 2>/dev/null || true
      fi
    done

    # Structural gate: no ABI-shadow (bundle soname resolved to nixpkgs)
    # and no dangling NEEDED anywhere in the extracted container tree.
    ${modern.verify-closure {
      out = "$out";
      bundleDirs = [
        "$out/lib"
        "$out/lib64"
        "$out/tensorrt_llm/lib"
        "$out/tensorrt_llm/libs"
        "$out/tensorrt_llm/libs/ucx"
        "$out/tensorrt_llm/libs/ucx/ucx"
        "${containerSrc}/opt/hpcx/ompi/lib"
        "${containerSrc}/opt/hpcx/ucc/lib"
        "${containerSrc}/opt/hpcx/ucx/lib"
      ];
      # Flatten runtime-inputs to individual lib dirs (verify-closure wants a
      # list of dirs, not a colon-joined string).
      systemFloor = lib.concatMap (d: let p = d.lib or d.out or d; in [ "${p}/lib" "${p}/lib64" ]) runtime-inputs;
      # Provided by the host at runtime (driver / RDMA fabric hardware).
      ignore = [ "libcuda.so.1" "libnvidia-ml.so.1" "libnvidia-*.so*" ];
    }}
  '';

  preFixup = ''
    addAutoPatchelfSearchPath $out/lib
    if [ -d "$out/tensorrt_llm/lib" ]; then
      addAutoPatchelfSearchPath $out/tensorrt_llm/lib
    fi
    if [ -d "$out/tensorrt_llm/libs" ]; then
      addAutoPatchelfSearchPath $out/tensorrt_llm/libs
    fi
    # NGC 26.06 ships the HPC-X stack (OpenMPI libmpi.so.40, UCC libucc.so.1
    # for collectives, UCX transports) under /opt/hpcx — load-bearing for
    # multi-node collectives across the fabric.
    for d in \
      ${containerSrc}/opt/hpcx/ompi/lib \
      ${containerSrc}/opt/hpcx/ucc/lib \
      ${containerSrc}/opt/hpcx/ucx/lib; do
      [ -d "$d" ] && addAutoPatchelfSearchPath "$d"
    done
    # MKL (torch linalg backend) lives in the container's /usr/local/lib. That
    # dir has no glibc/core libs, so it is safe to expose directly.
    [ -d "${containerSrc}/usr/local/lib" ] && addAutoPatchelfSearchPath ${containerSrc}/usr/local/lib
    # NOTE: do NOT addAutoPatchelfSearchPath the container's /usr/lib/<arch> or
    # /lib/<arch> — those carry the container's glibc (libc.so.6, libpthread),
    # which would land on RPATH ahead of the Nix glibc and crash at startup with
    # "undefined symbol: __nptl_change_stack_perm, version GLIBC_PRIVATE".
    # libgdrapi is copied out selectively in installPhase instead.
    ${modern.patch-elf {
      inherit runpath;
      out = "$out";
    }}
  '';

  # We invoke autoPatchelf manually in postFixup so the RUNPATH
  # sanitizer runs *after* it (autoPatchelf re-adds container arch
  # libdirs otherwise). Disable the automatic postFixup hook.
  dontAutoPatchelf = true;

  postFixup = ''
    # Run autoPatchelf first (auto-hook disabled via dontAutoPatchelf),
    # THEN sanitize RUNPATHs, THEN wrap — strip must not be re-clobbered.
    autoPatchelf "$out"

    # Sanitize RUNPATHs: autoPatchelf/patch-elf can record the container's arch
    # libdirs (…/ngc-26.06-rootfs/{lib,usr/lib}/<arch>) — which hold the
    # container glibc — into RUNPATH, where they shadow the Nix loader's glibc
    # and crash startup (__nptl_change_stack_perm / GLIBC_PRIVATE). Strip any
    # rootfs arch-libdir entry from every ELF; the fabric/CUDA libs we actually
    # need are already resolved from $out/lib, nvidia-sdk, and /opt/hpcx.
    echo "Stripping container arch libdirs from RUNPATHs..."
    # Guarded so it can never fail the build (set -e safe). Reads DT_RUNPATH via
    # readelf (this patchelf's --print-rpath returns empty for RUNPATH-only ELFs).
    strip_container_rpaths() {
      local f rp clean
      while IFS= read -r f; do
        rp=$(readelf -d "$f" 2>/dev/null | grep -E "RUNPATH|RPATH" | sed -E 's/.*\[(.*)\]/\1/' || true)
        [ -z "$rp" ] && continue
        case "$rp" in
          *-linux-gnu*)
            clean=$(printf '%s' "$rp" | tr ':' '\n' \
              | grep -vE 'rootfs/(lib|usr/lib)/(aarch64|x86_64)-linux-gnu' \
              | paste -sd: - || true)
            patchelf --set-rpath "$clean" "$f" 2>/dev/null || true
            ;;
        esac
      done
    }
    find "$out" -type f \( -name "*.so*" -o -perm -0100 \) 2>/dev/null | strip_container_rpaths || true
    # LD_LIBRARY_PATH set from wrapperLibPaths (glibc-free) — see binding above.

    for exe in $out/bin/*; do
      [ -f "$exe" ] && [ -x "$exe" ] || continue
      wrapProgram "$exe" \
        --set TRITON_SERVER_ROOT "$out" \
        --suffix LD_LIBRARY_PATH : "${wrapperLibPaths}" \
        --prefix PYTHONPATH : "$out/python"
    done
  '';

  passthru = {
    pythonPath = "$out/python";
  };

  meta = {
    description = "NVIDIA Triton Inference Server with TensorRT-LLM ${version}";
    homepage = "https://developer.nvidia.com/nvidia-triton-inference-server";
    # NGC container extraction includes proprietary components (TensorRT-LLM, cuDNN, etc.)
    license = lib.licenses.unfree;
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    mainProgram = "tritonserver";
  };
}
