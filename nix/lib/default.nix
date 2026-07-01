# nix/lib/default.nix — NVIDIA SDK Library Functions
#
# Unified library functions for building NVIDIA packages with consistent
# patterns, validation, and metadata.

{ lib }:

let
  # Import sub-modules
  mkNvidiaPackage = import ./mk-nvidia-package.nix { inherit lib; };
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

  # Convenience re-exports
  inherit (mkNvidiaPackage) mkNvidiaPackage;
  inherit (schemas) versionSchemas;
  inherit (validators) validateVersion assertCompatible;
  inherit (licenses)
    nvidiaCuda
    nvidiaCudnn
    nvidiaTensorrt
    nvidiaCutensor
    ;
}
