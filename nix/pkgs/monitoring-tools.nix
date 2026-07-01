{
  lib,
  writeShellScriptBin,
  symlinkJoin,
  cuda,
  btop,
  nvtopPackages,
}:

let
  # nvidia-smi wrapper from CUDA toolkit
  nvidia-smi = writeShellScriptBin "nvidia-smi" ''
    exec ${cuda}/bin/nvidia-smi "$@"
  '';

  # btop with NVML support enabled
  btop-nvml = btop.override { cudaSupport = true; };

  # nvtop with NVIDIA support
  nvtop = nvtopPackages.nvidia;

  # Combined monitoring tools package
  monitoring-tools = symlinkJoin {
    name = "gpu-monitoring-tools";

    paths = [
      nvidia-smi
      btop-nvml
      nvtop
    ];

    postBuild = ''
            # Create a convenience wrapper for quick GPU monitoring
            mkdir -p $out/bin
            cat > $out/bin/gpu-monitor <<'EOF'
      #!/usr/bin/env bash
      # Quick GPU monitoring dashboard

      echo "=== GPU Status (nvidia-smi) ==="
      ${nvidia-smi}/bin/nvidia-smi
      echo ""
      echo "Available monitoring tools:"
      echo "  nvtop        - Interactive GPU process monitor"
      echo "  btop         - System monitor with GPU support"
      echo "  nvidia-smi   - NVIDIA GPU status and management"
      EOF
            chmod +x $out/bin/gpu-monitor
    '';

    meta = {
      description = "GPU monitoring tools: nvidia-smi, btop with NVML, and nvtop";

      # btop (Apache-2.0), nvtop (GPL-3.0), nvidia-smi wrapper (MIT)
      license = [
        lib.licenses.asl20
        lib.licenses.gpl3Only
        lib.licenses.mit
      ];

      platforms = lib.platforms.linux;
    };
  };
in
{
  inherit
    nvidia-smi
    btop-nvml
    nvtop
    monitoring-tools
    ;

  # Export individual components for direct access
  btop = btop-nvml;
}
