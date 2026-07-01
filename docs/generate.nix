# docs/generate.nix — Documentation Generator
#
# Auto-generates documentation from code to ensure consistency.
# Generates compatibility matrices, package inventories, and option references.

{ pkgs }:

let
  inherit (pkgs) lib;

  # Import the canonical flat versions file (no args needed)
  versions = import ../nix/versions.nix;

  # CUDA-Driver compatibility (mirrors nix/lib/validators.nix)
  compatMatrix = {
    "13.0.0" = {
      minDriver = "580.65.06";
      status = "legacy";
    };
    "13.0.1" = {
      minDriver = "580.82.07";
      status = "legacy";
    };
    "13.0.2" = {
      minDriver = "580.95.05";
      status = "stable";
    };
    "13.1" = {
      minDriver = "590.44.01";
      status = "current";
    };
  };

  # Generate compatibility matrix
  compatibilityMatrix = pkgs.writeText "compatibility-matrix.md" ''
    # CUDA Version Compatibility Matrix

    Automatically generated from nix/versions.nix

    | CUDA Version | Minimum Driver | Status | Notes |
    |--------------|----------------|--------|-------|
    ${lib.concatMapStrings (
      ver:
      let
        info = compatMatrix.${ver};
      in
      "| ${ver} | ${info.minDriver} | ${info.status} | ${
        if info.status == "current" then
          "✅ Default"
        else if info.status == "stable" then
          "✓ Supported"
        else
          "⚠ Legacy"
      } |\n"
    ) (lib.attrNames compatMatrix)}

    ## Driver Compatibility Notes

    - NVIDIA drivers are **backward compatible**
    - Each CUDA version has a **minimum required driver**
    - Newer drivers work with older CUDA versions
    - Always use the latest driver for your hardware

    ## Checking Your Versions

    ```bash
    # CUDA version
    nvcc --version

    # Driver version
    nvidia-smi

    # Kernel module version
    cat /proc/driver/nvidia/version
    ```
  '';

  # Generate package inventory
  packageInventory = pkgs.writeText "package-inventory.md" ''
    # Package Inventory

    Automatically generated from nix/versions.nix

    ## Core SDK Components

    | Package | Version | Source | Description |
    |---------|---------|--------|-------------|
    | CUDA Toolkit | ${versions.cuda.version} | NVIDIA | Complete CUDA development toolkit |
    | cuDNN | ${versions.cudnn.version} | NVIDIA | Deep neural network primitives |
    | NCCL | ${versions.nccl.version} | NVIDIA | Multi-GPU collective communications |
    | TensorRT | ${versions.tensorrt.version} | NVIDIA | Inference optimization |
    | cuTensor | ${versions.cutensor.version} | NVIDIA | Tensor operations library |
    | CUTLASS | ${versions.cutlass.version} | GitHub | CUDA templates for linear algebra |

    ## Container Components

    | Component | Version | Source |
    |-----------|---------|--------|
    | NGC Base | ${versions.ngc.version} | NVIDIA GPU Cloud |
    | Triton Server | ${versions.triton-trtllm-container.version} | NGC Container |

    ## Architecture Support

    All packages support:
    - ✅ x86_64-linux
    - ✅ aarch64-linux (SBSA)

    ## Version Compatibility

    See [Compatibility Matrix](compatibility-matrix.md) for CUDA/driver compatibility.
  '';

  # Generate module options reference
  generateModuleOptions = pkgs.writeShellScriptBin "generate-module-options" ''
    set -e

    OUT_FILE=''${1:-module-options.md}

    cat > $OUT_FILE << 'HEADER'
    # NixOS Module Options Reference

    Automatically generated from nix/modules/nvidia-sdk.nix

    ## Core Options

    | Option | Type | Default | Description |
    |--------|------|---------|-------------|
    HEADER

    # Extract options from the module file
    grep -E "^\s*(enable|cudaVersion|driver|openKernelModule|nvidiaPersistenced|container|monitoring|opengl|powerManagement|systemPackages|wrapPrograms|expose) =" nix/modules/nvidia-sdk.nix | \
    while read line; do
      option=$(echo "$line" | sed 's/=.*$//' | xargs)
      echo "| hardware.nvidia-sdk.$option | ... | ... | ... |" >> $OUT_FILE
    done

    echo "" >> $OUT_FILE
    echo "See [NIXOS-MODULE.md](NIXOS-MODULE.md) for detailed documentation." >> $OUT_FILE

    echo "Generated $OUT_FILE"
  '';

  # Main documentation generator
  generateDocs = pkgs.writeShellScriptBin "generate-docs" ''
    set -e

    OUT_DIR=''${1:-./generated}
    mkdir -p $OUT_DIR

    echo "Generating NVIDIA SDK documentation..."
    echo ""

    # Copy generated files
    cp ${compatibilityMatrix} $OUT_DIR/compatibility-matrix.md
    echo "✓ Generated compatibility-matrix.md"

    cp ${packageInventory} $OUT_DIR/package-inventory.md
    echo "✓ Generated package-inventory.md"

    # Generate module options
    ${generateModuleOptions} $OUT_DIR/module-options.md
    echo "✓ Generated module-options.md"

    echo ""
    echo "Documentation generated in $OUT_DIR/"
    echo ""
    echo "Files:"
    ls -la $OUT_DIR/
  '';

in
{
  inherit generateDocs generateModuleOptions;

  # Export generated files for inspection
  files = { inherit compatibilityMatrix packageInventory; };

  # Run generator
  run = generateDocs;
}
