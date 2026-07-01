# nix/versions/default.nix — Version Configuration with Validation
#
# Centralized version management with schema validation and compatibility checking.
# All NVIDIA SDK component versions are defined here with validation.

{ lib }:

let
  # Import schemas and validators
  schemas = import ../lib/schemas.nix { inherit lib; };
  validators = import ../lib/validators.nix { inherit lib schemas; };

  # Import individual version definitions
  cudaVersions = import ./cuda { inherit lib; };
  cudnnVersions = import ./cudnn { inherit lib; };
  ncclVersions = import ./nccl { inherit lib; };
  tensorrtVersions = import ./tensorrt { inherit lib; };
  cutensorVersions = import ./cutensor { inherit lib; };
  cutlassVersions = import ./cutlass { inherit lib; };
  ngcVersions = import ./ngc { inherit lib; };
  driverVersions = import ./driver { inherit lib; };
  nsightVersions = import ./nsight { inherit lib; };
  smVersions = import ./sm { inherit lib; };

  # Combine all versions
  allVersions = {
    inherit (cudaVersions) cuda;
    inherit (cudnnVersions) cudnn;
    inherit (ncclVersions) nccl;
    inherit (tensorrtVersions) tensorrt;
    inherit (cutensorVersions) cutensor;
    inherit (cutlassVersions) cutlass;
    inherit (ngcVersions) ngc;
    inherit (driverVersions) driver;
    inherit (nsightVersions) nsight;
    inherit (smVersions) sm;
  };

  # Validate all versions
  validation = validators.validateVersions allVersions;

  # CUDA-Driver compatibility matrix
  compatibilityMatrix = {
    "13.0.0" = {
      minDriver = "580.65.06";
      maxDriver = null;
      status = "legacy";
    };
    "13.0.1" = {
      minDriver = "580.82.07";
      maxDriver = null;
      status = "legacy";
    };
    "13.0.2" = {
      minDriver = "580.95.05";
      maxDriver = null;
      status = "stable";
    };
    "13.1" = {
      minDriver = "590.44.01";
      maxDriver = null;
      status = "current";
    };
  };

  # Helper functions
  helpers = {
    # Check if a CUDA version is compatible with a driver version
    checkCompatibility =
      cudaVersion: driverVersion:
      let
        req = compatibilityMatrix.${cudaVersion} or null;
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
          inherit (req) status;
        };

    # Get the default CUDA version
    defaultCudaVersion = "13.1";

    # Get the default driver version
    defaultDriverVersion = "590.44.01";

    # Assert compatibility at evaluation time
    assertCompatible =
      cudaVersion: driverVersion:
      let
        result = helpers.checkCompatibility cudaVersion driverVersion;
      in
      assert lib.assertMsg result.compatible result.reason;
      true;
  };

in

# Assert validation passed
assert lib.assertMsg validation.valid
  "Version validation failed: ${lib.concatStringsSep "; " validation.errors}";

# Return all versions with helpers
allVersions
// {
  inherit validation compatibilityMatrix;
  lib = helpers;
}
