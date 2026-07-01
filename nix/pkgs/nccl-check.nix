{
  writeShellApplication,
  nccl-tests,
  openmpi,
}:

writeShellApplication {
  name = "nccl-check";

  runtimeInputs = [
    nccl-tests
    openmpi
  ];

  text = ''
    set -e

    echo "=== NCCL Validation Check ==="
    echo ""

    # Ensure driver library is available
    if [ -d /run/opengl-driver/lib ]; then
      export LD_LIBRARY_PATH="/run/opengl-driver/lib:''${LD_LIBRARY_PATH:-}"
    fi

    # Detect GPUs
    if ! command -v nvidia-smi &> /dev/null; then
      echo "✗ nvidia-smi not found. Is the NVIDIA driver installed?"
      exit 1
    fi

    GPU_COUNT=$(nvidia-smi --list-gpus 2>/dev/null | wc -l)

    if [ "$GPU_COUNT" -eq 0 ]; then
      echo "✗ No NVIDIA GPUs detected"
      exit 1
    fi

    echo "✓ Found $GPU_COUNT NVIDIA GPU(s):"
    nvidia-smi --query-gpu=index,name,compute_cap --format=csv,noheader | \
      while IFS=, read -r idx name cap; do
        echo "  [$idx] $name (compute $cap)"
      done
    echo ""

    # Run appropriate test based on GPU count
    if [ "$GPU_COUNT" -eq 1 ]; then
      echo "Running single-GPU NCCL test..."
      echo ""
      ${nccl-tests}/bin/all_reduce_perf -b 8 -e 128M -f 2 -g 1 -n 10 -w 5
    else
      echo "Running multi-GPU NCCL test ($GPU_COUNT GPUs)..."
      echo ""
      mpirun -np "$GPU_COUNT" --bind-to none -x LD_LIBRARY_PATH \
        ${nccl-tests}/bin/all_reduce_perf -b 8 -e 128M -f 2 -g 1 -n 10 -w 5
    fi

    echo ""
    echo "=== NCCL Check Complete ==="
  '';
}
