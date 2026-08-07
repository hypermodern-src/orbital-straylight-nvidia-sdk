# nvidia-sdk

Production-grade NVIDIA CUDA SDK for NixOS with complete driver integration, container runtime
support, and headless server capabilities.

> Part of the straylight build — this repo's book (the SDK, the nv cell) lives in [`doc/`](doc/)
> (`cd doc && buck2 build //:book`); the cross-repo hub book is
> [`straylight-mdbook`](https://git.s4.gl/straylight/straylight-mdbook).

**📚 [Complete Documentation Index](DOCS.md)**

**Key Features:**

- ✅ Complete CUDA 13.3.1 SDK (toolkit, cuDNN, NCCL, TensorRT, etc.)
- ✅ NixOS module with automatic driver management
- ✅ Container runtime support (Docker/Podman GPU access via CDI)
- ✅ nvidia-persistenced for headless/server reliability
- ✅ Matched 610.43.02 driver with backward compatibility
- ✅ x86_64-linux and aarch64-linux support
- ✅ Slim Triton + TensorRT-LLM package with an OpenAI-compatible frontend

## Quick Start

### As a Flake Input

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nvidia-sdk.url = "github:weyl-ai/nvidia-sdk";
  };

  outputs = { self, nixpkgs, nvidia-sdk }: {
    nixosConfigurations.your-host = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        nvidia-sdk.nixosModules.default
        {
          nixpkgs.overlays = [ nvidia-sdk.overlays.default ];
          
           hardware.nvidia-sdk = {
             enable = true;

             # Driver config
             driver.open = true;          # Open kernel module (Turing+)

             # Server features (all enabled by default)
             persistenced = true;          # Keep GPU initialized
             container.enable = true;      # Docker/Podman GPU access

             # SDK in PATH + monitoring tools
             systemPackages = true;        # nvidia-sdk in systemPackages
             monitoring = true;            # nvtop + btop with NVML
           };
        }
      ];
    };
  };
}
```

## What You Get

### CUDA SDK Components

| Package | Version | Source | | --- | --- | --- | | **CUDA Toolkit** | 13.3.1 | NVIDIA installer |
| **cuDNN** | 9.25.0.15 | NVIDIA redistrib | | **NCCL** | 2.30.7 | NVIDIA redistrib | | **TensorRT**
| 10.15.1.29 | NVIDIA redistrib | | **cuTensor** | 2.7.0.5 | NVIDIA redistrib | | **CUTLASS** |
4.6.1 | GitHub | | **Triton Server / TensorRT-LLM** | 26.06 / 1.2.1 | NGC container |

The TensorRT-LLM-only Triton closure and its in-process OpenAI frontend are available without
pulling the vLLM image:

```bash
triton_root="$(nix build --no-link --print-out-paths .#tritonserver-trtllm)"
nix run .#triton-openai -- \
  --model-repository "$triton_root/share/tritonserver/model-repositories/llmapi" \
  --openai-port 8000
```

The package installs the upstream repository template under
`share/tritonserver/model-repositories/llmapi`.

### NixOS Module Features

#### 1. Automatic Driver Management

The module handles NVIDIA driver installation and configuration:

```nix
hardware.nvidia-sdk = {
  enable = true;
  # Driver auto-managed by nixpkgs (recommended)
  # Override with: driver.package = config.boot.kernelPackages.nvidiaPackages.stable;
  driver.open = true;  # Open kernel module (Turing+)
};
```

**Driver Compatibility:**

- Drivers are backward compatible
- CUDA 13.3.1 requires driver ≥ 610.43.02 (the matched release — see nix/versions.nix)
- Works with: 590.44.01, any 590.x+

#### 2. NVIDIA Persistenced (Enabled by Default)

Keeps GPU initialized for headless/server workloads:

```nix
hardware.nvidia-sdk.persistenced = true;  # default
```

**Why you need this:**

- GPU stays initialized without X11/Wayland
- Eliminates cold-start delays (crucial for containers)
- Essential for production compute workloads
- Prevents random failures in containerized applications

**When to disable:**

- Laptops where battery life matters
- Desktop systems that power down GPU when idle

#### 3. Container Runtime Support (Enabled by Default)

Automatic Docker/Podman GPU access via CDI:

```nix
hardware.nvidia-sdk.container.enable = true;  # default
```

**What it does:**

- Installs nvidia-container-toolkit
- Enables CDI (Container Device Interface) in Docker
- Configures Podman if enabled

**Usage:**

```bash
# Docker
docker run --device nvidia.com/gpu=all nvidia/cuda:13.0.2-base nvidia-smi

# Docker Compose
services:
  gpu-workload:
    image: nvidia/cuda:13.0.2-base
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: 1
              capabilities: [gpu]
```

#### 4. System Packages & Monitoring

Control what gets added to `environment.systemPackages`:

```nix
hardware.nvidia-sdk = {
  systemPackages = true;   # default: add nvidia-sdk to PATH
  monitoring = true;       # default: add nvtop + btop with NVML
};
```

When `systemPackages` is true, `CUDA_PATH` and `CUDA_HOME` environment variables are also set
globally.

## Driver 590.x Series

### Compatibility Matrix

CUDA 13.3.1 pairs with driver 610.43.02 (see nix/versions.nix); the 590-series table below is the
prior 13.1-era guidance:

| Driver Version | Release Date | Status | |----------------|--------------|--------| | 590.44.01 |
Jan 2026 | Minimum for CUDA 13.3.1 | | 590.54.01 | Feb 2026 | ✅ Recommended | | 590.65.01 | Mar 2026
| ✅ Latest stable |

### Checking Your Driver

```bash
# Kernel module version
cat /proc/driver/nvidia/version

# Userspace library version
nvidia-smi

# Check persistence mode
nvidia-smi | grep "Persistence-M"
# Should show "On" if nvidiaPersistenced is enabled
```

### Open vs Proprietary Driver

The 590.x series supports both:

**Open Kernel Module** (Turing+ GPUs):

```nix
hardware.nvidia-sdk.openKernelModule = true;
```

**Proprietary Driver** (All GPUs):

```nix
hardware.nvidia-sdk.openKernelModule = false;
```

## Command Line Usage

```bash
# Dev shell with full SDK
nix develop github:weyl-ai/nvidia-sdk

# Build individual components
nix build github:weyl-ai/nvidia-sdk#cuda
nix build github:weyl-ai/nvidia-sdk#cudnn
nix build github:weyl-ai/nvidia-sdk#nccl
nix build github:weyl-ai/nvidia-sdk#tensorrt
nix build github:weyl-ai/nvidia-sdk#nvidia-sdk  # Unified SDK

# GPU monitoring (nvidia-smi always available from driver)
nvidia-smi
# Install btop/nvtop separately via your preferred method
```

## Configuration Examples

### Example 1: Server/Compute Node

```nix
hardware.nvidia-sdk = {
  enable = true;

  # Open kernel module (Turing+)
  driver.open = true;

  # Server defaults (all true by default)
  persistenced = true;       # Critical for servers
  container.enable = true;   # Docker GPU access
  systemPackages = true;     # nvidia-sdk in PATH
  monitoring = true;         # nvtop + btop
};
```

### Example 2: ML Development Workstation

```nix
hardware.nvidia-sdk = {
  enable = true;
  driver.open = true;

  # Everything in PATH for development
  systemPackages = true;
  monitoring = true;
};
```

### Example 3: Container Platform (Kubernetes/K3s)

```nix
hardware.nvidia-sdk = {
  enable = true;
  driver.open = true;

  # Essential for K8s
  persistenced = true;       # Prevents GPU unload
  container.enable = true;   # Automatic GPU access

  # Containers handle their own CUDA — no need for system-wide SDK
  systemPackages = false;
};

# Then deploy NVIDIA device plugin:
# kubectl apply -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/main/deployments/static/nvidia-device-plugin.yml
```

## Module Options Reference

### Core Options

| Option | Type | Default | Description | |--------|------|---------|-------------| | `enable` |
bool | false | Enable NVIDIA SDK | | `systemPackages` | bool | true | Add nvidia-sdk to
environment.systemPackages | | `monitoring` | bool | true | Install nvtop + btop with NVML |

### Driver Options

| Option | Type | Default | Description | |--------|------|---------|-------------| |
`driver.package` | package | nvidiaPackages.latest | NVIDIA driver package | | `driver.open` | bool
| true | Use open kernel module (Turing+) |

### Server/Container Options

| Option | Type | Default | Description | |--------|------|---------|-------------| | `persistenced`
| bool | **true** | Enable persistence daemon | | `container.enable` | bool | **true** | Enable
container GPU access |

When `monitoring = true`, the module installs `nvtop` and `btop` (with NVML support). `nvidia-smi`
is always available from the driver.

## Architecture

### File Structure

```
nix/
├── versions.nix          # Single source of truth for versions
├── cuda.nix              # CUDA toolkit from installer
├── cudnn.nix             # cuDNN from redistrib
├── nccl.nix              # NCCL from NGC container
├── tensorrt.nix          # TensorRT from redistrib
├── cutensor.nix          # cuTensor from redistrib
├── cutlass.nix           # CUTLASS from GitHub
├── nvidia-sdk.nix        # Unified SDK package
├── tritonserver.nix      # Triton Inference Server
└── modules/
    └── nvidia-sdk.nix    # NixOS module

docs/
├── DRIVER-580-GUIDE.md   # Driver 580.x series guide
└── NIXOS-MODULE.md       # Complete module documentation

examples/
├── driver-580-config.nix # Example configuration
└── nixos-configuration.nix
```

### Design Principles

1. **Single Source of Truth**: All versions in `nix/versions.nix`
2. **Explicit Dependencies**: No global pollution unless requested
3. **Production-Ready**: Persistenced, container support, reliability
4. **Backward Compatible**: Driver compatibility clearly documented
5. **Composable**: Use as overlay, module, or both

## Troubleshooting

### GPU Not Found in Container

**Symptom:** `docker run --device nvidia.com/gpu=all` fails

**Solution:**

1. Check persistenced: `systemctl status nvidia-persistenced`
2. Verify CDI: Check Docker has `features.cdi = true`
3. Ensure driver loaded: `nvidia-smi`

### Driver/Library Version Mismatch

**Symptom:** `Failed to initialize NVML: Driver/library version mismatch`

**Cause:** Kernel module and userspace libraries don't match

**Solution:**

```bash
# Check versions
cat /proc/driver/nvidia/version  # Kernel module
nvidia-smi | head -3             # Userspace

# If mismatch, rebuild
sudo nixos-rebuild switch
```

### CUDA Not Found

**Symptom:** Programs can't find CUDA

**Solution:**

- Ensure `systemPackages = true` (default) or add `pkgs.nvidia-sdk` to your user packages.
- Check: `echo $CUDA_PATH`
- Restart your shell after `nixos-rebuild switch`.

### Persistence Mode Disabled

**Symptom:** `Persistence-M` shows "Off" in nvidia-smi

**Solution:**

```nix
hardware.nvidia-sdk.persistenced = true;
```

Then: `sudo nixos-rebuild switch`

## Documentation

### User Documentation

- **[NixOS Module Reference](docs/NIXOS-MODULE.md)** - Complete module options and examples
- **[Driver 580.x Guide](docs/DRIVER-580-GUIDE.md)** - Driver compatibility and troubleshooting
- **[Example Configurations](examples/)** - Ready-to-use NixOS configs

### Development Documentation

- **[Blackwell Investigation](docs/archive/BLACKWELL-SM120-INVESTIGATION.md)** - SM120 CUTLASS
  bring-up journal
- **[CUDA stdenv Link Line](docs/archive/CUDA-STDENV-LINK-LINE.md)** - Manual compilation reference
- **[stdenv Architecture](docs/archive/stdenvs.md)** - Custom stdenv design notes

## Trust & Reproducibility

All binary artifacts are fetched with pinned SRI hashes in `nix/versions.nix`. The hash is the
security boundary — regardless of where a file is downloaded from, a hash mismatch aborts the build.

**What you're trusting:**

| Component | Source | Trust boundary | |-----------|--------|---------------| | CUDA toolkit |
`developer.download.nvidia.com` | SHA-256 hash in `versions.nix` | | cuDNN, TensorRT, cuTensor |
mirror (`nvidia-redistributable.weyl.ai`) or upstream NVIDIA | SHA-256 hash in `versions.nix` | |
NCCL | PyPI wheel or mirror | SHA-256 hash in `versions.nix` | | NGC container (Triton, Python) |
`nvcr.io` via `crane export` | FOD hash in `versions.nix` | | CUTLASS | GitHub release tarball |
SHA-256 hash in `versions.nix` | | Binary cache | `weyl-ai.cachix.org` | Cachix signing key in
`flake.nix` |

**To disable the binary cache** (build everything from source):

```bash
nix build .#nvidia-sdk --option substituters ""
```

The mirror URLs (`nvidia-redistributable.weyl.ai`) are tried before upstream NVIDIA URLs. If you
prefer upstream-only fetches, swap the URL order in `nix/versions.nix` or remove the mirror entries.

## Development

```bash
# Clone repo
git clone https://github.com/weyl-ai/nvidia-sdk
cd nvidia-sdk

# Enter dev shell
nix develop

# Build SDK
nix build .#nvidia-sdk
```

### Validation

Before submitting changes, run these checks:

```bash
# Fast: verify all packages evaluate (no build, both arches)
nix flake check --no-build --all-systems

# Medium: build the unified SDK
nix build .#nvidia-sdk

# Full: run flake checks (requires build)
nix flake check
```

### Update tooling

```bash
# Check for newer NVIDIA redistributable versions
nix run .#update

# Environment variables for R2 mirror upload (optional):
#   UPLOAD_TO_R2=true R2_BUCKET=... R2_ENDPOINT=...
```

## Contributing

This is a production configuration used in production GPU clusters. Changes should:

1. Maintain backward compatibility
2. Be tested on real hardware
3. Pass `nix flake check --no-build --all-systems`
4. Update documentation

## License

- **Nix expressions**: MIT License (see [LICENSE](LICENSE))
- **NVIDIA binary components**: Subject to
  [NVIDIA's proprietary licenses](https://docs.nvidia.com/cuda/eula/)
- **NCCL, CUTLASS**: BSD-3-Clause

See [THIRD-PARTY-LICENSES.md](THIRD-PARTY-LICENSES.md) for full details.

**Note:** By using this SDK, you agree to comply with the
[NVIDIA End User License Agreement](https://www.nvidia.com/en-us/drivers/nvidia-license/).

## Support

- Issues: GitHub Issues
- Docs: `docs/` directory
- Examples: `examples/` directory

______________________________________________________________________

**Production-tested on:**

- 4x NVIDIA RTX PRO 6000 (Ampere)
- NVIDIA driver 590.44.01 (open kernel module)
- CUDA 13.3.1
- NixOS unstable (2026-02)
