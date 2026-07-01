# tests/unit/default.nix — Unit Tests
#
# Fast tests that don't require GPU or building packages.
# Tests version parsing, validation, and Nix expression evaluation.
#
# Uses the flat nix/versions.nix (canonical source of truth) and
# nix/lib/ for validators/schemas.

{ pkgs }:

let
  inherit (pkgs) lib;

  # Import the canonical versions file (flat attrset, no args)
  versions = import ../../nix/versions.nix;

  # Import lib modules for validation tests
  schemas = import ../../nix/lib/schemas.nix { inherit lib; };
  validators = import ../../nix/lib/validators.nix { inherit lib schemas; };

  # Test runner — each test is an assertion in Nix; if it evaluates, it passes.
  runTest =
    name: expr:
    pkgs.runCommand "test-${name}" { } ''
      echo "Running test: ${name}"
      ${expr}
      echo "PASS" > $out
    '';

  # ──────────────────────────────────────────────────────────────────────────
  # Version Tests
  # ──────────────────────────────────────────────────────────────────────────
  versionTests = {
    # Test that versions.nix evaluates and has a CUDA version
    versions-eval = ''
      test -n "${versions.cuda.version}" || (echo "cuda.version is empty" && exit 1)
    '';

    # Test CUDA version format (must be 13.x)
    cuda-version-format = ''
      echo "${versions.cuda.version}" | ${pkgs.gnugrep}/bin/grep -q "^13\." || \
        (echo "CUDA version does not start with 13.: ${versions.cuda.version}" && exit 1)
    '';

    # Test that all required top-level keys exist
    versions-keys = ''
      # These are string interpolations — if any key is missing, Nix eval fails
      echo "cuda:     ${versions.cuda.version}"
      echo "cudnn:    ${versions.cudnn.version}"
      echo "nccl:     ${versions.nccl.version}"
      echo "tensorrt: ${versions.tensorrt.version}"
      echo "cutensor: ${versions.cutensor.version}"
      echo "cutlass:  ${versions.cutlass.version}"
      echo "ngc:      ${versions.ngc.version}"
      echo "driver:   ${versions.driver.version}"
    '';

    # Test that per-arch source info exists for x86_64
    x86-sources = ''
      test -n "${versions.cuda.x86_64-linux.url}" || (echo "missing cuda x86_64 url" && exit 1)
      test -n "${versions.cudnn.x86_64-linux.hash}" || (echo "missing cudnn x86_64 hash" && exit 1)
      test -n "${versions.nccl.x86_64-linux.hash}" || (echo "missing nccl x86_64 hash" && exit 1)
      test -n "${versions.tensorrt.x86_64-linux.hash}" || (echo "missing tensorrt x86_64 hash" && exit 1)
    '';

    # Test that per-arch source info exists for aarch64
    aarch64-sources = ''
      test -n "${versions.cuda.aarch64-linux.url}" || (echo "missing cuda aarch64 url" && exit 1)
      test -n "${versions.cudnn.aarch64-linux.hash}" || (echo "missing cudnn aarch64 hash" && exit 1)
      test -n "${versions.nccl.aarch64-linux.hash}" || (echo "missing nccl aarch64 hash" && exit 1)
      test -n "${versions.tensorrt.aarch64-linux.hash}" || (echo "missing tensorrt aarch64 hash" && exit 1)
    '';

    # Test compatibility checker from validators.nix
    compatibility-compatible = ''
      ${
        let
          result = validators.checkCompatibility "13.1" "590.44.01";
        in
        if result.compatible then
          ''
            echo "13.1 + 590.44.01: compatible=true (OK)"
          ''
        else
          ''
            echo "FAIL: 13.1 + 590.44.01 should be compatible but got: ${result.reason}" && exit 1
          ''
      }
    '';

    compatibility-incompatible = ''
      ${
        let
          result = validators.checkCompatibility "13.1" "580.00.00";
        in
        if !result.compatible then
          ''
            echo "13.1 + 580.00.00: compatible=false (OK, expected)"
          ''
        else
          ''
            echo "FAIL: 13.1 + 580.00.00 should be incompatible" && exit 1
          ''
      }
    '';

    # Test schema validation
    schema-validation = ''
      ${
        let
          result = schemas.validateVersion "cuda" {
            version = "13.1";
            driver = "590.44.01";
            url = "https://example.com";
            hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
          };
        in
        if result.valid then
          ''
            echo "Schema validation: valid (OK)"
          ''
        else
          ''
            echo "FAIL: schema validation should pass but got errors: ${lib.concatStringsSep ", " result.errors}" && exit 1
          ''
      }
    '';

    # Test that driver hashes are still placeholders (reminder to fix)
    driver-hash-placeholder = ''
      echo "Checking driver hash placeholder status..."
      ${
        let
          hash = versions.driver.x86_64-linux.hash;
        in
        if lib.hasPrefix "sha256-AAAAAAA" hash then
          ''
            echo "WARNING: driver hash is still a placeholder (expected during development)"
          ''
        else
          ''
            echo "Driver hash looks real: ${hash}"
          ''
      }
    '';
  };

  # ──────────────────────────────────────────────────────────────────────────
  # Build all tests
  # ──────────────────────────────────────────────────────────────────────────
  builtTests = lib.mapAttrs (name: test: runTest name test) versionTests;

  # ──────────────────────────────────────────────────────────────────────────
  # Test runner script
  # ──────────────────────────────────────────────────────────────────────────
  runTests = pkgs.writeShellScriptBin "run-unit-tests" ''
    set -e

    echo "═══════════════════════════════════════════════════════════"
    echo "  Unit Tests"
    echo "═══════════════════════════════════════════════════════════"
    echo ""

    failed=0
    ${lib.concatMapStrings (name: ''
      echo "Testing ${name}..."
      if [ -f "${builtTests.${name}}" ]; then
        echo "  ✓ ${name}"
      else
        echo "  ✗ ${name}"
        failed=1
      fi
    '') (lib.attrNames builtTests)}

    echo ""
    if [ $failed -eq 0 ]; then
      echo "✓ All unit tests passed"
      exit 0
    else
      echo "✗ Some unit tests failed"
      exit 1
    fi
  '';

in
{
  tests = builtTests;
  run = runTests;
}
