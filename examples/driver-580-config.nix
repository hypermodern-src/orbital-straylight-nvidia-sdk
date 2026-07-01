# Example configuration for driver 580.x / 590.x series
# Works with the latest nixpkgs driver packages
#
# Usage: Import this in your NixOS configuration

{ inputs, ... }:

{
  imports = [ inputs.nvidia-sdk.nixosModules.default ];

  nixpkgs.overlays = [ inputs.nvidia-sdk.overlays.default ];

  nixpkgs.config.allowUnfree = true;

  hardware.nvidia-sdk = {
    enable = true;

    # Use open kernel module (580.119.02+ supports open)
    driver.open = true;

    # Override driver package if you need a specific version:
    # driver.package = config.boot.kernelPackages.nvidiaPackages.stable;

    # Server features (all true by default)
    persistenced = true; # Keep GPU initialized for headless/server
    container.enable = true; # Docker/Podman GPU via CDI

    # System integration
    systemPackages = true; # nvidia-sdk in PATH
    monitoring = true; # nvtop + btop with NVML
  };

  # Verify your driver version matches:
  # Run: cat /proc/driver/nvidia/version
  # Should show: NVRM version: NVIDIA UNIX Open Kernel Module for x86_64 580.xxx.xx
}
