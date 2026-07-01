# modern.nix — Primitives for content-addressed builds
#
# Provides:
#   - mk-runpath: construct LD runpath from dependencies
#   - patch-elf: fix interpreter and runpath for all ELFs
#   - extract: unpack tarball/archive, patch rpaths
#   - container-to-nix: extract container filesystem (FOD)
#   - verify-closure: fail the build if any ELF has a lurking linkage bomb
#
# ──────────────────────────────────────────────────────────────────────────────
# Closure policy (why verify-closure exists)
# ──────────────────────────────────────────────────────────────────────────────
# Our vendor-blob packages (nvidia-sdk, tritonserver, ngc-python) ship their own
# ABI-matched shared libraries — a full Qt6, CUDA userspace, HPC-X, TRT-LLM, etc.
# The ONLY correct linkage policy is: the vendor's bundled libs win, and nixpkgs
# supplies just the irreducible system floor. Two failure modes hide otherwise,
# and only surface when the binary is actually executed on target hardware:
#
#   MODE 1 (ABI shadow): an ELF resolves a soname to a NIXPKGS copy when the SAME
#     soname also exists in the vendor bundle → two incompatible builds of one
#     library load into the process → GLIBC_PRIVATE / Qt_6_PRIVATE_API crashes.
#
#   MODE 2 (dangling NEEDED): an ELF NEEDs a soname that resolves nowhere on its
#     RPATH → "cannot open shared object file" at startup.
#
# `verify-closure` walks every ELF in $out at build time and fails the build on
# either mode, so a package cannot even be produced with a hidden linkage bomb.
# This replaces the reactive "run it on the GB10 and see what breaks" loop with a
# structural guarantee shared by every vendor-blob package.

final: _prev:
let
  inherit (final) lib;

  # ════════════════════════════════════════════════════════════════════════════
  # mk-runpath — construct ld runpath from dependencies
  # ════════════════════════════════════════════════════════════════════════════

  mk-runpath =
    deps:
    lib.concatStringsSep ":" (
      lib.concatMap
        (
          dep:
          let
            d = dep.lib or dep.out or dep;
          in
          [
            "${d}/lib"
            "${d}/lib64"
          ]
        )
        deps
    );

  # ════════════════════════════════════════════════════════════════════════════
  # patch-elf — fix interpreter and runpath for all ELFs
  # ════════════════════════════════════════════════════════════════════════════

  patch-elf = { runpath, out }: ''
    find ${out} -type f \( -executable -o -name "*.so*" \) 2>/dev/null | while read -r f; do
      if file "$f" | grep -q ELF; then
        if file "$f" | grep -q "executable"; then
          patchelf --set-interpreter "$(cat ${final.stdenv.cc}/nix-support/dynamic-linker)" "$f" 2>/dev/null || true
        fi
        existing=$(patchelf --print-rpath "$f" 2>/dev/null || echo "")
        new_rpath="${runpath}:${out}/lib:${out}/lib64''${existing:+:$existing}"
        patchelf --set-rpath "$new_rpath" "$f" 2>/dev/null || true
      fi
    done
  '';

  # ════════════════════════════════════════════════════════════════════════════
  # verify-closure — structural gate against the two linkage failure modes
  # ════════════════════════════════════════════════════════════════════════════
  #
  #   verify-closure {
  #     out        = "$out";
  #     bundleDirs = [ "$out/nsight-.../host-linux-x64" ... ];  # vendor's own libs
  #     systemFloor = [ "${glibc}/lib" ... ];                    # nixpkgs floor
  #     ignore     = [ "libcuda.so.1" "libnvidia-ml.so.1" ];     # host-provided at runtime
  #   }
  #
  # For every ELF under `out`, resolve each DT_NEEDED against the union of the
  # ELF's own dir, bundleDirs, systemFloor, and its recorded RUNPATH/RPATH:
  #   - MODE 2: any NEEDED (not in `ignore`) that resolves nowhere → fail.
  #   - MODE 1: any NEEDED whose soname ALSO exists in a bundleDir but resolved to
  #     a non-bundle (nixpkgs) path first → fail (ABI shadow).
  verify-closure =
    { out
    , bundleDirs ? [ ]
    , systemFloor ? [ ]
    , ignore ? [ ]
    ,
    }:
    let
      bundleArr = lib.concatStringsSep " " (map (d: ''"${d}"'') bundleDirs);
      floorArr = lib.concatStringsSep " " (map (d: ''"${d}"'') systemFloor);
      ignoreArr = lib.concatStringsSep " " (map (s: ''"${s}"'') ignore);
    in
    ''
      echo "verify-closure: auditing ELF linkage under ${out} ..."
      _vc_bundle_dirs=( ${bundleArr} )
      _vc_floor_dirs=( ${floorArr} )
      _vc_ignore=( ${ignoreArr} )

      # Is soname $1 provided by any bundle dir? echo the path, else nothing.
      _vc_in_bundle() {
        local soname="$1" d
        for d in "''${_vc_bundle_dirs[@]}"; do
          [ -e "$d/$soname" ] && { echo "$d/$soname"; return 0; }
        done
        return 1
      }
      # Resolve soname $1 for ELF $2 against: own dir, RUNPATH, bundle, floor.
      # Echoes the resolving dir (first match), or nothing.
      _vc_resolve() {
        local soname="$1" elf="$2" owndir rp d
        owndir=$(dirname "$elf")
        local search=( "$owndir" )
        rp=$(patchelf --print-rpath "$elf" 2>/dev/null || true)
        [ -z "$rp" ] && rp=$(readelf -d "$elf" 2>/dev/null | grep -E "RUNPATH|RPATH" | sed -E 's/.*\[(.*)\]/\1/' || true)
        if [ -n "$rp" ]; then
          IFS=':' read -ra _rps <<< "$rp"
          for d in "''${_rps[@]}"; do search+=( "$d" ); done
        fi
        search+=( "''${_vc_bundle_dirs[@]}" "''${_vc_floor_dirs[@]}" )
        for d in "''${search[@]}"; do
          [ -n "$d" ] && [ -e "$d/$soname" ] && { echo "$d"; return 0; }
        done
        return 1
      }
      _vc_is_ignored() {
        local n="$1" g
        for g in "''${_vc_ignore[@]}"; do
          case "$n" in $g) return 0;; esac
        done
        return 1
      }
      # glibc core + the loader come from the runtime environment (they are the
      # ABI floor every Linux process gets); never treat them as dangling.
      _vc_is_core() {
        case "$1" in
          libc.so.6|libm.so.6|libpthread.so.0|librt.so.1|libdl.so.2| \
          libutil.so.1|libresolv.so.2|ld-linux*.so.*|ld-linux*.so.2|libnsl.so.*) return 0;;
        esac
        return 1
      }

      _vc_fail=0
      while IFS= read -r elf; do
        [ -L "$elf" ] && continue
        file "$elf" 2>/dev/null | grep -q ELF || continue
        # Only audit native 64-bit ELFs. Vendor SDKs ship 32-bit (i386) injection
        # shims (compute-sanitizer/x86/…) that are LD_PRELOAD'd into arbitrary
        # target processes and resolve libc from the target; we ship no 32-bit
        # floor and must not gate on them.
        readelf -h "$elf" 2>/dev/null | grep -q "ELF64" || continue
        while IFS= read -r need; do
          [ -z "$need" ] && continue
          _vc_is_ignored "$need" && continue
          _vc_is_core "$need" && continue
          resolved=$(_vc_resolve "$need" "$elf" || true)
          if [ -z "$resolved" ]; then
            echo "verify-closure: MODE2 dangling: $elf needs $need (resolves nowhere)" >&2
            _vc_fail=1
            continue
          fi
          # MODE 1: soname also exists in the vendor bundle, but we resolved it
          # to a NON-bundle (nixpkgs/floor) path -> ABI shadow. Resolving to any
          # bundle dir (its own dir or a sibling vendor dir) is fine; only a
          # nixpkgs copy winning over a bundled soname is the bug.
          if _vc_in_bundle "$need" >/dev/null; then
            _vc_resolved_ok=0
            # Resolving to the ELF's OWN dir is always fine (the vendor lib
            # sitting next to it), as is any declared bundle dir. Only a nixpkgs
            # path winning over a bundled soname is the ABI-shadow bug.
            [ "$resolved" = "$(dirname "$elf")" ] && _vc_resolved_ok=1
            for d in "''${_vc_bundle_dirs[@]}"; do
              [ "$resolved" = "$d" ] && { _vc_resolved_ok=1; break; }
            done
            # Any path *inside* $out is vendor content, never nixpkgs.
            case "$resolved" in "${out}"/*) _vc_resolved_ok=1;; esac
            if [ "$_vc_resolved_ok" -eq 0 ]; then
              echo "verify-closure: MODE1 ABI-shadow: $elf resolved $need to non-bundle $resolved (bundle provides this soname)" >&2
              _vc_fail=1
            fi
          fi
        done < <(patchelf --print-needed "$elf" 2>/dev/null || true)
      done < <(find "${out}" -type f \( -executable -o -name "*.so*" \) 2>/dev/null)

      if [ "$_vc_fail" -ne 0 ]; then
        echo "verify-closure: FAILED — lurking linkage issues above. Fix RPATH/bundle ordering or the system floor." >&2
        exit 1
      fi
      echo "verify-closure: OK — no ABI-shadow or dangling NEEDED under ${out}."
    '';

in
{
  modern = {
    inherit mk-runpath patch-elf verify-closure;

    # ══════════════════════════════════════════════════════════════════════════
    # extract — unpack tarball/archive, patch rpaths
    # ══════════════════════════════════════════════════════════════════════════

    extract =
      { pname
      , version
      , src
      , runtime-inputs ? [ ]
      , install ? "cp -a . $out/"
      , post-install ? ""
      , meta ? { }
      , ...
      }:
      let
        runpath = mk-runpath runtime-inputs;
      in
      final.stdenv.mkDerivation {
        inherit
          pname
          version
          src
          meta
          ;

        nativeBuildInputs = [
          final.patchelf
          final.file
          final.findutils
          final.gnugrep
          final.gnutar
          final.gzip
          final.xz
          final.unzip
        ];

        dontConfigure = true;
        dontBuild = true;
        dontUnpack = true;

        installPhase = ''
          runHook preInstall
          mkdir -p $out
          ${install}
          ${post-install}
          runHook postInstall
        '';

        fixupPhase = ''
          runHook preFixup
          ${patch-elf {
            inherit runpath;
            out = "$out";
          }}
          runHook postFixup
        '';
      };

    # ══════════════════════════════════════════════════════════════════════════
    # container-to-nix — extract container filesystem (FOD)
    # ══════════════════════════════════════════════════════════════════════════

    container-to-nix =
      { name
      , imageRef
      , hash
      ,
      }:
      let
        # Map Nix system to OCI platform
        platform = if final.stdenv.hostPlatform.isAarch64 then "linux/arm64" else "linux/amd64";
      in
      final.stdenvNoCC.mkDerivation {
        inherit name;

        nativeBuildInputs = [
          final.crane
          final.gnutar
          final.gzip
        ];

        outputHashAlgo = "sha256";
        outputHashMode = "recursive";
        outputHash = hash;

        SSL_CERT_FILE = "${final.cacert}/etc/ssl/certs/ca-bundle.crt";

        buildCommand = ''
          mkdir -p $out
          crane export --platform ${platform} ${imageRef} - | tar -xf - -C $out
        '';
      };
  };
}
