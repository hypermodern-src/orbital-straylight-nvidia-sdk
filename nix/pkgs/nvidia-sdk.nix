{
  lib,
  stdenv,
  symlinkJoin,
  makeWrapper,
  patchelf,
  bash,
  coreutils,
  cuda,
  cudnn,
  cutensor,
  cutlass,
  dbus,
  file,
  findutils,
  gnugrep,
  libglvnd,
  mesa,
  nccl,
  qt6,
  resholve,
  tensorrt,
  versions,
  xorg,
}:

let
  # Nsight version and path data from versions.nix
  ncuVersion = versions.nsight.compute.version;
  ncuDir = "nsight-compute-${ncuVersion}";
  ncuHostPath = versions.nsight.compute.${stdenv.hostPlatform.system}.path;

  nsysVersion = versions.nsight.systems.version;
  nsysDir = "nsight-systems-${nsysVersion}";
  nsysHostPath = versions.nsight.systems.${stdenv.hostPlatform.system}.path;

  patchElfScript = resholve.mkDerivation {
    pname = "patch-nvidia-elfs";
    version = "1.0.0";

    src = ../scripts;

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
  };

  merged = symlinkJoin {
    name = "nvidia-sdk-${versions.cuda.version}";

    paths = [
      cuda
      cudnn
      nccl
      tensorrt
      cutlass
      cutensor
    ];

    postBuild = ''
      for dir in lib lib64 include; do
        if [ -L "$out/$dir" ]; then
          target=$(readlink "$out/$dir")
          rm "$out/$dir"
          mkdir -p "$out/$dir"
          cp -rL "$target"/* "$out/$dir/" 2>/dev/null || true
        fi
      done
    '';
  };

in
stdenv.mkDerivation {
  pname = "nvidia-sdk";
  version = versions.cuda.version;

  dontUnpack = true;
  nativeBuildInputs = [
    makeWrapper
    patchelf
    file
  ];
  buildInputs = [
    merged
    qt6.qtbase
    qt6.qtwayland
    mesa
    libglvnd
    xorg.libX11
    xorg.libXext
    xorg.libXrender
    xorg.libxcb
    stdenv.cc.cc.lib
  ];

  installPhase = ''
    mkdir -p $out/{bin,lib64,include,nvvm,share,nix-support}

    # Copy bin, nvvm, share directories
    for dir in bin nvvm share; do
      if [ -e "${merged}/$dir" ]; then
        cp -rL "${merged}/$dir"/* "$out/$dir/" 2>/dev/null || true
      fi
    done

    # Copy Nsight and profiling tools from CUDA
    if [ -d "${cuda}/${ncuDir}" ]; then
      cp -rL "${cuda}/${ncuDir}" "$out/" 2>/dev/null || true
    fi
    if [ -d "${cuda}/${nsysDir}" ]; then
      cp -rL "${cuda}/${nsysDir}" "$out/" 2>/dev/null || true
    fi
    if [ -d "${cuda}/extras/CUPTI/lib64" ]; then
      echo "Copying CUPTI libraries..."
      cp -rL "${cuda}/extras/CUPTI/lib64"/* "$out/lib64/" 2>/dev/null || true
    fi
    if [ -d "${cuda}/compute-sanitizer" ]; then
      cp -rL "${cuda}/compute-sanitizer" "$out/" 2>/dev/null || true
    fi
    if [ -d "${cuda}/nsightee_plugins" ]; then
      cp -rL "${cuda}/nsightee_plugins" "$out/" 2>/dev/null || true
    fi

    # Copy headers from all packages
    for pkg in ${cuda} ${cudnn} ${nccl} ${tensorrt} ${cutlass} ${cutensor}; do
      if [ -d "$pkg/include" ] && [ ! -L "$pkg/include" ]; then
        cp -rL "$pkg/include"/* "$out/include/" 2>/dev/null || true
      elif [ -L "$pkg/include" ]; then
        target=$(readlink -f "$pkg/include")
        [ -d "$target" ] && cp -rL "$target"/* "$out/include/" 2>/dev/null || true
      fi

      # Also copy target-specific headers from CUDA
      if [ -d "$pkg/targets/x86_64-linux/include" ]; then
        cp -rL "$pkg/targets/x86_64-linux/include"/* "$out/include/" 2>/dev/null || true
      fi
      if [ -d "$pkg/targets/aarch64-linux/include" ]; then
        cp -rL "$pkg/targets/aarch64-linux/include"/* "$out/include/" 2>/dev/null || true
      fi
    done

    # Merge all libraries from both lib and lib64 into $out/lib64
    # This handles the different directory structures across packages
    for pkg in ${cuda} ${cudnn} ${nccl} ${tensorrt} ${cutlass} ${cutensor}; do
      for libdir in lib lib64; do
        if [ -d "$pkg/$libdir" ] && [ ! -L "$pkg/$libdir" ]; then
          cp -rL "$pkg/$libdir"/* "$out/lib64/" 2>/dev/null || true
        elif [ -L "$pkg/$libdir" ]; then
          target=$(readlink -f "$pkg/$libdir")
          [ -d "$target" ] && cp -rL "$target"/* "$out/lib64/" 2>/dev/null || true
        fi
      done
    done

    [ ! -e "$out/lib" ] && ln -sf lib64 $out/lib

    mkdir -p $out/lib64/stubs

    # Ensure pkgconfig directory is writable
    chmod -R +w $out/lib64/pkgconfig 2>/dev/null || true
    mkdir -p $out/lib64/pkgconfig

    cat > $out/nix-support/setup-hook << 'EOF'
    export CUDA_HOME="@out@"
    export CUDA_PATH="@out@"
    export CUDNN_HOME="@out@"
    export TENSORRT_HOME="@out@"
    export CUTLASS_PATH="@out@/include/cutlass"
    export PATH="@out@/bin''${PATH:+:$PATH}"
    export LD_LIBRARY_PATH="@out@/lib64:@out@/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    export LIBRARY_PATH="@out@/lib64:@out@/lib''${LIBRARY_PATH:+:$LIBRARY_PATH}"
    export C_INCLUDE_PATH="@out@/include''${C_INCLUDE_PATH:+:$C_INCLUDE_PATH}"
    export CPLUS_INCLUDE_PATH="@out@/include''${CPLUS_INCLUDE_PATH:+:$CPLUS_INCLUDE_PATH}"
    export PKG_CONFIG_PATH="@out@/lib64/pkgconfig''${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
    EOF
    sed -i "s|@out@|$out|g" $out/nix-support/setup-hook

    cat > $out/version.json << EOF
    {
      "cuda": "${versions.cuda.version}",
      "cudnn": "${versions.cudnn.version}",
      "nccl": "${versions.nccl.version}",
      "tensorrt": "${versions.tensorrt.version}",
      "cutlass": "${versions.cutlass.version}",
      "cutensor": "${versions.cutensor.version}"
    }
    EOF

    cat > $out/bin/nvidia-sdk-validate << 'VALIDATE'
    #!/bin/bash
    echo "NVIDIA SDK Components:"
    for lib in cudart cublas cufft curand cusolver cusparse nvrtc cudnn nccl nvinfer cutensor cupti; do
      if ls @out@/lib64/lib$lib*.so* >/dev/null 2>&1; then
        echo "  ✓ $lib"
      else
        echo "  ✗ $lib"
      fi
    done
    echo ""
    cat @out@/version.json
    VALIDATE
    sed -i "s|@out@|$out|g" $out/bin/nvidia-sdk-validate
    chmod +x $out/bin/nvidia-sdk-validate

    mkdir -p $out/lib64/pkgconfig
    cat > $out/lib64/pkgconfig/nvidia-sdk.pc << PC
    prefix=$out
    libdir=\''${prefix}/lib64
    includedir=\''${prefix}/include

    Name: NVIDIA SDK
    Description: Unified NVIDIA CUDA development environment
    Version: ${versions.cuda.version}
    Libs: -L\''${libdir} -lcudart -lcudnn -lnccl -lnvinfer -lcutensor
    Cflags: -I\''${includedir}
    PC

    # Copy LICENSE files from component packages
    mkdir -p $out/share/licenses

    copy_license() {
      local pkg="$1"
      local name="$2"
      local found=false

      for license_file in LICENSE LICENSE.txt EULA.txt EULA license.txt License.txt LICENSE.md; do
        if [ -f "$pkg/$license_file" ]; then
          cp "$pkg/$license_file" "$out/share/licenses/LICENSE-$name.txt"
          found=true
          break
        fi
        # Also check in share directory
        if [ -f "$pkg/share/$license_file" ]; then
          cp "$pkg/share/$license_file" "$out/share/licenses/LICENSE-$name.txt"
          found=true
          break
        fi
        # Check in share/doc
        if [ -f "$pkg/share/doc/$license_file" ]; then
          cp "$pkg/share/doc/$license_file" "$out/share/licenses/LICENSE-$name.txt"
          found=true
          break
        fi
      done

      if [ "$found" = false ]; then
        echo "Warning: No license file found for $name"
      fi
    }

    copy_license "${cuda}" "cuda"
    copy_license "${cudnn}" "cudnn"
    copy_license "${nccl}" "nccl"
    copy_license "${tensorrt}" "tensorrt"
    copy_license "${cutlass}" "cutlass"
    copy_license "${cutensor}" "cutensor"
  '';

  dontStrip = true;
  dontMoveLib64 = true;
  dontWrapQtApps = true;

  postFixup =
    let
      qtLibs = "${qt6.qtbase}/lib";
      mesaLibs = "${mesa}/lib:${libglvnd}/lib";
      x11Libs = "${xorg.libX11}/lib:${xorg.libXext}/lib:${xorg.libXrender}/lib:${xorg.libxcb}/lib";
      sysLibs = "${stdenv.cc.cc.lib}/lib:${dbus}/lib";
      nsightLibs = "$out/${ncuDir}/${ncuHostPath}:$out/${nsysDir}/${nsysHostPath}:$out/${nsysDir}/target-linux-${
        if stdenv.hostPlatform.isAarch64 then "sbsa" else "x64"
      }";
      dynamicLinker = "$(cat ${stdenv.cc}/nix-support/dynamic-linker)";
    in
    ''
      ${patchElfScript}/bin/patch-nvidia-elfs \
        "$out" \
        "${qtLibs}" \
        "${mesaLibs}" \
        "${x11Libs}" \
        "${sysLibs}" \
        "${nsightLibs}" \
        "${dynamicLinker}"
    '';

  passthru = {
    inherit
      versions
      cuda
      cudnn
      nccl
      tensorrt
      cutlass
      cutensor
      ;

    cudaVersion = versions.cuda.version;
    cudnnVersion = versions.cudnn.version;
  };

  meta = {
    description = "NVIDIA CUDA SDK ${versions.cuda.version}";
    homepage = "https://developer.nvidia.com/cuda-toolkit";
    license = lib.licenses.unfree;

    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];

    mainProgram = "nvcc";
  };
}
