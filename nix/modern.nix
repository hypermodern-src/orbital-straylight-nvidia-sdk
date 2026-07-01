# modern.nix — Primitives for content-addressed builds
#
# Provides:
#   - mk-runpath: construct LD runpath from dependencies
#   - patch-elf: fix interpreter and runpath for all ELFs
#   - extract: unpack tarball/archive, patch rpaths
#   - container-to-nix: extract container filesystem (FOD)

final: _prev:
let
  inherit (final) lib;

  # ════════════════════════════════════════════════════════════════════════════
  # mk-runpath — construct ld runpath from dependencies
  # ════════════════════════════════════════════════════════════════════════════

  mk-runpath =
    deps:
    lib.concatStringsSep ":" (
      lib.concatMap (
        dep:
        let
          d = dep.lib or dep.out or dep;
        in
        [
          "${d}/lib"
          "${d}/lib64"
        ]
      ) deps
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

in
{
  modern = {
    inherit mk-runpath patch-elf;

    # ══════════════════════════════════════════════════════════════════════════
    # extract — unpack tarball/archive, patch rpaths
    # ══════════════════════════════════════════════════════════════════════════

    extract =
      {
        pname,
        version,
        src,
        runtime-inputs ? [ ],
        install ? "cp -a . $out/",
        post-install ? "",
        meta ? { },
        ...
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
      {
        name,
        imageRef,
        hash,
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
