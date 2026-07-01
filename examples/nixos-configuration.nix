# Example NixOS configuration using nvidia-sdk
#
# This example shows how to declaratively configure NVIDIA CUDA on NixOS
# using the nvidia-sdk flake.

{ pkgs, inputs, ... }:

{
  imports = [
    # Import the NVIDIA SDK NixOS module
    inputs.nvidia-sdk.nixosModules.default
  ];

  # Apply the overlay to get CUDA packages
  nixpkgs.overlays = [ inputs.nvidia-sdk.overlays.default ];

  # ════════════════════════════════════════════════════════════════════════════
  # NVIDIA SDK Configuration
  # ════════════════════════════════════════════════════════════════════════════

  hardware.nvidia-sdk = {
    enable = true;

    # ──────────────────────────────────────────────────────────────────────────
    # Driver
    # ──────────────────────────────────────────────────────────────────────────

    # Use open-source kernel module (required for Blackwell, recommended for Turing+)
    driver.open = true;

    # Override driver package if needed (defaults to nvidiaPackages.latest):
    # driver.package = config.boot.kernelPackages.nvidiaPackages.stable;

    # ──────────────────────────────────────────────────────────────────────────
    # System Integration
    # ──────────────────────────────────────────────────────────────────────────

    # Add nvidia-sdk to PATH (nvcc, cuda-gdb, etc.) and set CUDA_PATH/CUDA_HOME
    systemPackages = true; # default

    # GPU monitoring tools (nvtop + btop with NVML)
    monitoring = true; # default

    # ──────────────────────────────────────────────────────────────────────────
    # Services
    # ──────────────────────────────────────────────────────────────────────────

    # nvidia-persistenced for headless/server use
    persistenced = true; # default

    # Container GPU passthrough (Docker/Podman with CDI)
    container.enable = true; # default
  };

  # ════════════════════════════════════════════════════════════════════════════
  # Docker (if using containers)
  # ════════════════════════════════════════════════════════════════════════════

  virtualisation.docker.enable = true;

  # ════════════════════════════════════════════════════════════════════════════
  # Additional packages from overlay (optional)
  # ════════════════════════════════════════════════════════════════════════════

  environment.systemPackages = [
    # Development
    pkgs.cuda-samples
    pkgs.cutlass

    # Profiling (GUI)
    pkgs.nsight-gui-apps
  ];
}

# ══════════════════════════════════════════════════════════════════════════════
# Usage in flake.nix
# ══════════════════════════════════════════════════════════════════════════════
#
# {
#   inputs = {
#     nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
#     nvidia-sdk.url = "github:weyl-ai/nvidia-sdk";
#   };
#
#   outputs = { nixpkgs, nvidia-sdk, ... }: {
#     nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
#       system = "x86_64-linux";
#       specialArgs = { inherit inputs; };
#       modules = [ ./configuration.nix ];
#     };
#   };
# }
#
# ══════════════════════════════════════════════════════════════════════════════
# Minimal Example
# ══════════════════════════════════════════════════════════════════════════════
#
# hardware.nvidia-sdk = {
#   enable = true;
#   driver.open = true;
# };
#
# That's it! The module handles:
# - Driver installation with correct kernel module
# - OpenGL/Vulkan setup
# - nvidia-persistenced service
# - Container runtime (CDI)
# - Modesetting for Wayland
