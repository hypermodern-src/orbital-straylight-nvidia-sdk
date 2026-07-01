# nvidia-sdk Documentation Index

Complete documentation for production NVIDIA CUDA on NixOS.

## Quick Links

- **[README.md](README.md)** - Start here: Features, quick start, examples
- **[NixOS Module Reference](docs/NIXOS-MODULE.md)** - Complete module options with examples
- **[Driver 580.x Guide](docs/DRIVER-580-GUIDE.md)** - Driver compatibility and troubleshooting
- **[Example Configurations](examples/)** - Copy-paste ready configs

## Documentation Structure

### For Users

1. **[README.md](README.md)** - Main documentation

   - Quick start with flakes
   - All SDK components
   - NixOS module features (persistenced, container runtime, etc.)
   - Configuration examples
   - Troubleshooting

2. **[docs/NIXOS-MODULE.md](docs/NIXOS-MODULE.md)** - Module reference

   - All configuration options
   - Detailed option descriptions
   - Container usage examples (Docker, Podman, K8s)
   - Complete configuration examples

3. **[docs/DRIVER-580-GUIDE.md](docs/DRIVER-580-GUIDE.md)** - Driver guide

   - Compatibility matrix
   - Version checking
   - Open vs proprietary drivers
   - Troubleshooting driver issues

4. **[examples/](examples/)** - Ready-to-use configs

   - Server/compute node setup
   - Development workstation
   - Container platform (K8s/K3s)
   - Driver 580.x configuration

### For Developers

5. **[docs/archive/BLACKWELL-SM120-INVESTIGATION.md](docs/archive/BLACKWELL-SM120-INVESTIGATION.md)**

   - Blackwell (SM120) bring-up journal
   - CUTLASS compilation investigation
   - nvcc vs Clang comparison
   - Device code generation debugging

6. **[docs/archive/CUDA-STDENV-LINK-LINE.md](docs/archive/CUDA-STDENV-LINK-LINE.md)**

   - Manual CUDA compilation reference
   - Complete link line breakdown
   - Include paths and library paths
   - Working command examples

7. **[docs/archive/stdenvs.md](docs/archive/stdenvs.md)**

   - Custom stdenv architecture
   - Compiler configuration
   - Build system design

## Common Tasks

### Getting Started

```bash
# 1. Add to flake inputs
inputs.nvidia-sdk.url = "github:weyl-ai/nvidia-sdk";

# 2. Import module
imports = [ nvidia-sdk.nixosModules.default ];

# 3. Add overlay
nixpkgs.overlays = [ nvidia-sdk.overlays.default ];

# 4. Enable
hardware.nvidia-sdk.enable = true;
```

See [README.md#quick-start](README.md#quick-start) for complete examples.

### Configuration

**Basic server setup:**

```nix
hardware.nvidia-sdk = {
  enable = true;
  driver.open = true;
};
```

**Production compute node:**

```nix
hardware.nvidia-sdk = {
  enable = true;
  driver.open = true;
  persistenced = true;       # Keep GPU alive (default)
  container.enable = true;   # Docker GPU access (default)
  systemPackages = false;    # No global pollution
};
```

See [README.md#configuration-examples](README.md#configuration-examples) for more.

### Troubleshooting

**GPU not found:**

1. Check driver: `nvidia-smi`
2. Check persistence: `systemctl status nvidia-persistenced`
3. Verify: `cat /proc/driver/nvidia/version`

**Container GPU access failed:**

1. Check CDI: Docker daemon should have `features.cdi = true`
2. Ensure persistenced running
3. Test: `docker run --device nvidia.com/gpu=all nvidia/cuda:13.0.2-base nvidia-smi`

**Driver mismatch:**

```bash
# Check versions
cat /proc/driver/nvidia/version  # Kernel
nvidia-smi | head -3             # Userspace

# Rebuild if mismatch
sudo nixos-rebuild switch
```

See [README.md#troubleshooting](README.md#troubleshooting) for detailed solutions.

## Module Options Quick Reference

| Option | Default | Description | | ------------------ | --------------------- |
-------------------------------- | | `enable` | false | Enable NVIDIA SDK | | `driver.package` |
nvidiaPackages.latest | NVIDIA driver package | | `driver.open` | true | Open kernel module
(Turing+) | | `systemPackages` | true | Add nvidia-sdk to systemPackages | | `monitoring` | true |
Install nvtop + btop with NVML | | `persistenced` | **true** | Keep GPU initialized | |
`container.enable` | **true** | Docker/Podman GPU access |

See [docs/NIXOS-MODULE.md](docs/NIXOS-MODULE.md) for complete option reference.

## Driver Compatibility

CUDA 13.0.2 requires driver ≥ 580.95.05

**Compatible drivers:**

- 580.95.05 (minimum)
- 580.119.02 ✅ (recommended)
- 580.126.09 ✅ (latest)
- Any 580.x or 590.x ✅

See [docs/DRIVER-580-GUIDE.md](docs/DRIVER-580-GUIDE.md) for detailed compatibility info.

## Architecture Overview

```
nix/
├── versions.nix          # Version definitions (single source of truth)
├── cuda.nix              # CUDA toolkit
├── cudnn.nix             # Deep learning library
├── nccl.nix              # Multi-GPU communication
├── tensorrt.nix          # Inference optimization
├── nvidia-sdk.nix        # Unified SDK package
└── modules/
    └── nvidia-sdk.nix    # NixOS module with persistenced, containers, etc.
```

**Design principles:**

1. Single source of truth (`versions.nix`)
2. Explicit dependencies (no global pollution)
3. Production-ready (persistenced, container support)
4. Backward compatible (clear driver requirements)

## Support

- **Issues:** [GitHub Issues](https://github.com/weyl-ai/nvidia-sdk/issues)
- **Examples:** See `examples/` directory
- **Questions:** Check troubleshooting sections first

## Contributing

See [README.md#contributing](README.md#contributing) for contribution guidelines.

______________________________________________________________________

**Production-tested:**

- Hardware: 4x NVIDIA RTX PRO 6000 (Ampere)
- Driver: 580.119.02 (open kernel module)
- CUDA: 13.0.2
- OS: NixOS unstable (2026-01)
