# nix/lib/mk-nvidia-package.nix — Unified NVIDIA Package Builder
#
# Provides a consistent interface for building all NVIDIA SDK packages
# with proper dependency management, ELF patching, and metadata.

{ lib, fetchurl, fetchFromGitHub }:

{
  # Main package builder function
  mkNvidiaPackage =
    {
      pname,
      version,
      src ? null,
      tarball ? null,
      container ? null,
      git ? null,
      nativeBuildInputs ? [ ],
      buildInputs ? [ ],
      runtimeInputs ? [ ],
      installPhase ? null,
      installScript ? "",
      postInstall ? "",
      fixupPhase ? null,
      meta ? { },
      passthru ? { },
      ...
    }:
    let

      # Default metadata
      defaultMeta = {
        description = "NVIDIA ${pname} ${version}";
        homepage = "https://developer.nvidia.com/${pname}";
        license = lib.licenses.unfree;

        platforms = [
          "x86_64-linux"
          "aarch64-linux"
        ];

        maintainers = [ ];
      };

      mergedMeta = defaultMeta // meta;
    in
    {
      # Return the package definition (not built yet)
      inherit pname version;
      inherit
        src
        tarball
        container
        git
        ;

      buildConfig = {
        inherit nativeBuildInputs buildInputs runtimeInputs;

        inherit installPhase;
        inherit installScript;
        inherit postInstall;
        inherit fixupPhase;
      };

      meta = mergedMeta;
      inherit passthru;
    };

  # Build a package definition with actual stdenv
  buildPackage =
    {
      stdenv,
      modern,
      pkgDef,
    }:
    stdenv.mkDerivation {
      inherit (pkgDef) pname version;

      src =
        if pkgDef ? tarball && pkgDef.tarball != null then
          fetchurl {
            url = pkgDef.tarball.urls.mirror or pkgDef.tarball.urls.upstream;
            hash = pkgDef.tarball.hash;
          }

        else if pkgDef ? container && pkgDef.container != null then
          modern.container-to-nix {
            name = "${pkgDef.pname}-${pkgDef.version}-container";
            imageRef = pkgDef.container.imageRef;
            hash = pkgDef.container.hash;
          }

        else if pkgDef ? git && pkgDef.git != null then
          fetchFromGitHub {
            inherit (pkgDef.git)
              owner
              repo
              rev
              hash
              ;
          }
        else
          pkgDef.src;

      nativeBuildInputs = pkgDef.buildConfig.nativeBuildInputs;
      buildInputs = pkgDef.buildConfig.buildInputs;

      installPhase =
        if pkgDef.buildConfig.installPhase != null then
          pkgDef.buildConfig.installPhase
        else
          ''
            runHook preInstall
            mkdir -p $out
            ${pkgDef.buildConfig.installScript}
            runHook postInstall
          '';

      postInstall = pkgDef.buildConfig.postInstall;

      fixupPhase = if pkgDef.buildConfig.fixupPhase != null then pkgDef.buildConfig.fixupPhase else null;

      inherit (pkgDef) meta;
      inherit (pkgDef) passthru;
    };
}
