# tests/default.nix — NVIDIA SDK Test Suite
#
# Test entrypoint.  Only the unit suite exists today; build / integration /
# module suites are listed as TODO stubs so the runner doesn't break.

{ pkgs }:

let
  # Import test suites that actually exist
  unitTests = import ./unit { inherit pkgs; };

in
{
  inherit unitTests;

  # Combined test runner
  runAll = pkgs.writeShellScriptBin "run-nvidia-sdk-tests" ''
    set -e

    echo "═══════════════════════════════════════════════════════════"
    echo "  NVIDIA SDK Test Suite"
    echo "═══════════════════════════════════════════════════════════"
    echo ""

    failed=0

    # Run unit tests
    echo "┌─ Running Unit Tests"
    if ${unitTests.run}/bin/run-unit-tests; then
      echo "  ✓ Unit tests passed"
    else
      echo "  ✗ Unit tests failed"
      failed=1
    fi
    echo ""

    # TODO: build tests  (tests/build/)
    echo "┌─ Build Tests"
    echo "  ⊘ Skipped (not yet implemented)"
    echo ""

    # TODO: integration tests (tests/integration/) — require GPU
    echo "┌─ Integration Tests"
    echo "  ⊘ Skipped (not yet implemented)"
    echo ""

    # TODO: module tests (tests/module/)
    echo "┌─ Module Tests"
    echo "  ⊘ Skipped (not yet implemented)"
    echo ""

    # Summary
    echo "═══════════════════════════════════════════════════════════"
    if [ $failed -eq 0 ]; then
      echo "  ✓ All tests passed!"
      echo "═══════════════════════════════════════════════════════════"
      exit 0
    else
      echo "  ✗ Some tests failed"
      echo "═══════════════════════════════════════════════════════════"
      exit 1
    fi
  '';
}
