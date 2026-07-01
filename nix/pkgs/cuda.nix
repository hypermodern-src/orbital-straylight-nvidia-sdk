{
  lib,
  stdenv,
  buildFHSEnvBubblewrap,
  fetchurl,
  findutils,
  gnugrep,
  patchelf,
  file,
  libxml2,
  versions,
}:

let
  system = stdenv.hostPlatform.system;
  src-info = versions.cuda.${system} or (throw "cuda: unsupported system ${system}");

  libxml2LegacyVersion = "2.9.14";
  libxml2-legacy = libxml2.overrideAttrs (_: {
    version = libxml2LegacyVersion;

    src = fetchurl {
      url = "https://download.gnome.org/sources/libxml2/${lib.versions.majorMinor libxml2LegacyVersion}/libxml2-${libxml2LegacyVersion}.tar.xz";

      sha256 = "sha256-YNdKJX0czsBHXnScui8hVZ5IE577pv8oIkNXx8eY3+4=";
    };
  });

  fhs-env = buildFHSEnvBubblewrap {
    name = "cuda-installer-fhs";
    targetPkgs = pkgs: [
      pkgs.coreutils
      pkgs.curl
      pkgs.file
      pkgs.gcc
      pkgs.glibc
      pkgs.openssl
      pkgs.patchelf
      pkgs.perl
      pkgs.util-linux
      pkgs.which
      pkgs.xz
      pkgs.zlib
      libxml2-legacy # From outer scope
    ];
  };

  version = versions.cuda.version;

in
stdenv.mkDerivation {
  pname = "cuda";
  inherit version;

  src = fetchurl {
    inherit (src-info) url;
    inherit (src-info) hash;
  };

  nativeBuildInputs = [
    fhs-env
    patchelf
    file
    findutils
    gnugrep
  ];

  buildInputs = [ stdenv.cc.cc.lib ];

  dontStrip = true;
  dontUnpack = true;
  dontConfigure = true;

  buildPhase = ''
    ${fhs-env}/bin/cuda-installer-fhs -c "
      sh $src --silent --toolkit --toolkitpath=$out --no-opengl-libs --override
    "
    [ ! -e $out/lib ] && ln -sf lib64 $out/lib || true

    mkdir -p $out/lib64/stubs
    [ -f $out/lib64/libcuda.so ] && mv $out/lib64/libcuda.so $out/lib64/stubs/ || true
  '';

  installPhase = ''
        mkdir -p $out/lib64/pkgconfig
        cat > $out/lib64/pkgconfig/cuda.pc << 'EOF'
    prefix=$out
    libdir=''${prefix}/lib64
    includedir=''${prefix}/include

    Name: CUDA
    Description: NVIDIA CUDA Toolkit
    Version: ${version}
    Libs: -L''${libdir} -lcudart
    Cflags: -I''${includedir}
    EOF

        # Create symlink for Clang 21+ compatibility (texture_fetch_functions.h -> texture_indirect_functions.h)
        echo "Creating texture_fetch_functions.h symlinks for Clang CUDA compiler compatibility..."
        for target_dir in $out/include $out/targets/*/include; do
          if [ -d "$target_dir" ] && [ -f "$target_dir/texture_indirect_functions.h" ]; then
            echo "  Symlinking in: $target_dir"
            ( cd "$target_dir" && ln -sf texture_indirect_functions.h texture_fetch_functions.h )
            ls -la "$target_dir/texture_fetch_functions.h"
          fi
        done

        # Wrap fatbinary to strip unsupported flags
        if [ -f $out/bin/fatbinary ]; then
          cp $out/bin/fatbinary $out/bin/.fatbinary-real
          cat > $out/bin/fatbinary <<EOFWRAPPER
    #!/bin/sh
    args=""
    for arg in "\$@"; do
      case "\$arg" in
        -image|-image=*|--image|--image=*)
          # Skip -image flags (Clang compatibility)
          ;;
        --cicc-cmdline=*)
          # Strip prec_* options from cicc-cmdline that fatbinary doesn't understand
          value="\''${arg#--cicc-cmdline=}"
          value=\''$(echo "\$value" | sed 's/-prec_div=[^ ]*//g; s/-prec_sqrt=[^ ]*//g; s/-fmad=[^ ]*//g; s/-ftz=[^ ]*//g')
          args="\$args --cicc-cmdline=\"\$value\""
          ;;
        *)
          args="\$args \$arg"
          ;;
      esac
    done
    eval exec "$out/bin/.fatbinary-real" \$args
    EOFWRAPPER
          chmod +x $out/bin/fatbinary
        fi
  '';

  fixupPhase = ''
    runHook preFixup

    # Patch ELF files
    find $out -type f \( -executable -o -name "*.so*" \) 2>/dev/null | while read -r f; do
      [ -L "$f" ] && continue
      file "$f" | grep -q ELF || continue

      if file "$f" | grep -q "executable"; then
        patchelf --set-interpreter "$(cat ${stdenv.cc}/nix-support/dynamic-linker)" "$f" 2>/dev/null || true
      fi

      existing=$(patchelf --print-rpath "$f" 2>/dev/null || echo "")
      new_rpath="$out/lib:$out/lib64''${existing:+:$existing}"
      patchelf --set-rpath "$new_rpath" "$f" 2>/dev/null || true
    done

    runHook postFixup
  '';

  passthru = {
    inherit version;
    majorVersion = lib.versions.major version;

    inherit versions;
  };

  meta = {
    description = "NVIDIA CUDA Toolkit ${version}";
    homepage = "https://developer.nvidia.com/cuda-toolkit";

    license = lib.licenses.unfree;

    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
}
