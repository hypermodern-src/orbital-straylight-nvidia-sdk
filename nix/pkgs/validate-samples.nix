{
  writeShellScriptBin,
  cuda-samples,
  file,
  patchelf,
}:

writeShellScriptBin "validate-cuda-samples" ''
  set -e

  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  CUDA Samples Validation"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo

  # Check samples exist
  echo "┌─ Checking built samples"
  for sample in deviceQuery vectorAdd matrixMul; do
    if [ -x "${cuda-samples}/bin/$sample" ]; then
      echo "  ✓ $sample exists"
    else
      echo "  ✗ $sample missing"
      exit 1
    fi
  done
  echo

  # Check ELF linking
  echo "┌─ Checking CUDA linking"
  for sample in deviceQuery vectorAdd matrixMul; do
    if ${file}/bin/file "${cuda-samples}/bin/$sample" | grep -q ELF; then
      if ${patchelf}/bin/patchelf --print-needed "${cuda-samples}/bin/$sample" | grep -q libcudart; then
        echo "  ✓ $sample links to libcudart (runtime API)"
      else
        echo "  ℹ $sample uses driver API or static linking"
      fi
    fi
  done
  echo

  # Try to run (will fail without GPU, but should fail in the right way)
  echo "┌─ Testing sample execution (expected to fail without GPU)"
  for sample in deviceQuery vectorAdd matrixMul; do
    if ${cuda-samples}/bin/$sample 2>&1 | grep -q "CUDA driver version is insufficient\|cudaGetDeviceCount\|no CUDA-capable device\|cudaError"; then
      echo "  ✓ $sample runs and reports CUDA error (expected)"
    else
      echo "  ✗ $sample failed unexpectedly"
      exit 1
    fi
  done
  echo

  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  ✓ All sample validation checks passed!"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
''
