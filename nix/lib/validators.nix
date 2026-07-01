# nix/lib/validators.nix — Validation Utilities
#
# Provides validation functions for checking version compatibility,
# package integrity, and system requirements.

{ lib, schemas }:

let
  inherit (schemas) validateVersion;

  # Check if a CUDA version is compatible with a driver version
  checkCompatibility =
    cudaVersion: driverVersion:
    let
      # Compatibility matrix
      matrix = {
        "13.0.0" = {
          minDriver = "580.65.06";
        };
        "13.0.1" = {
          minDriver = "580.82.07";
        };
        "13.0.2" = {
          minDriver = "580.95.05";
        };
        "13.1" = {
          minDriver = "590.44.01";
        };
      };

      req = matrix.${cudaVersion} or null;
    in
    if req == null then
      {
        compatible = false;
        reason = "Unknown CUDA version: ${cudaVersion}";
      }
    else if lib.strings.versionOlder driverVersion req.minDriver then
      {
        compatible = false;
        reason = "Driver ${driverVersion} < minimum required ${req.minDriver} for CUDA ${cudaVersion}";
      }
    else
      {
        compatible = true;
        reason = "OK";
      };

  # Validate a complete versions configuration
  validateVersions =
    versions:
    let
      results = {
        cuda = validateVersion "cuda" versions.cuda;
        cudnn = validateVersion "cudnn" versions.cudnn;
        nccl = validateVersion "nccl" versions.nccl;
        tensorrt = validateVersion "tensorrt" versions.tensorrt;
        cutensor = validateVersion "cutensor" versions.cutensor;
        cutlass = validateVersion "cutlass" versions.cutlass;
        ngc = validateVersion "ngc" versions.ngc;
        driver = validateVersion "driver" versions.driver;
      };

      allValid = lib.all (r: r.valid) (lib.attrValues results);
      allErrors = lib.concatMap (name: lib.map (err: "${name}: ${err}") results.${name}.errors) (
        lib.attrNames results
      );
    in
    if allValid then
      {
        valid = true;
        errors = [ ];
      }
    else
      {
        valid = false;
        errors = allErrors;
      };

  # Assert compatibility at evaluation time
  assertCompatible =
    cudaVersion: driverVersion:
    let
      result = checkCompatibility cudaVersion driverVersion;
    in
    assert lib.assertMsg result.compatible result.reason;
    true;

in
{
  inherit checkCompatibility validateVersions assertCompatible;
}
