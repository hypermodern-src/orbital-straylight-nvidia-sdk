# Example NixOS configuration using nvidia-sdk module
#
# Demonstrates the recommended approach:
# - Open kernel module for Turing+ GPUs
# - Persistenced for headless/server reliability
# - Container runtime for Docker/Podman GPU access

{ inputs, ... }: {
  imports = [ inputs.nvidia-sdk.nixosModules.default ];

  nixpkgs.overlays = [ inputs.nvidia-sdk.overlays.default ];

  hardware.nvidia-sdk = {
    enable = true;

    # ──────────────────────────────────────────────────────────────────────
    # Driver
    # ──────────────────────────────────────────────────────────────────────

    driver.open = true; # Open kernel module (Turing+)

    # ──────────────────────────────────────────────────────────────────────
    # System integration
    # ──────────────────────────────────────────────────────────────────────

    systemPackages = true; # nvidia-sdk in PATH + CUDA_PATH set
    monitoring = true; # nvtop + btop with NVML

    # ──────────────────────────────────────────────────────────────────────
    # Server features (all true by default)
    # ──────────────────────────────────────────────────────────────────────

    persistenced = true; # Keep GPU initialized (headless)
    container.enable = true; # Docker/Podman GPU via CDI
  };
}
