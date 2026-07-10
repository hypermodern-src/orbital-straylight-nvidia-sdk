# nix/lib/default.nix — NVIDIA SDK Library Functions
#
# Unified library functions for building NVIDIA packages with consistent
# patterns, validation, and metadata.

{ lib }:

let
  # Import sub-modules
  mkNvidiaPackage = import ./mk-nvidia-package.nix {
    inherit lib;
    # fetchurl and fetchFromGitHub are injected by callers via callPackage
    fetchurl = throw "nvidiaLib: fetchurl must be provided by caller";
    fetchFromGitHub = throw "nvidiaLib: fetchFromGitHub must be provided by caller";
  };
  schemas = import ./schemas.nix { inherit lib; };
  validators = import ./validators.nix { inherit lib schemas; };
  licenses = import ./licenses.nix { inherit lib; };

in
{
  inherit
    mkNvidiaPackage
    schemas
    validators
    licenses
    ;

  # Convenience re-exports from mkNvidiaPackage module
  inherit (mkNvidiaPackage) buildPackage;
  inherit (schemas) versionSchemas;
  inherit (validators) validateVersion assertCompatible;
  inherit (licenses)
    nvidiaCuda
    nvidiaCudnn
    nvidiaTensorrt
    nvidiaCutensor
    ;
}
