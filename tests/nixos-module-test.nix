# Simple test to verify the NixOS module evaluates correctly
# Run with: nix eval --impure --expr 'import ./tests/nixos-module-test.nix {}'
#
# This test uses lib.evalModules with mock NixOS options to verify that
# the nvidia-sdk module declares its options and wires config correctly,
# WITHOUT requiring a full NixOS evaluation.

{
  pkgs ? import <nixpkgs> { },
  lib ? pkgs.lib,
}:
let
  # Minimal NixOS config evaluation
  eval = lib.evalModules {
    modules = [
      # Import our module (actual path)
      ../nix/modules/nvidia-sdk.nix

      # Minimal mock NixOS options that our module sets
      {
        options = {
          boot.kernelPackages = lib.mkOption {
            type = lib.types.attrs;
            default = pkgs.linuxPackages;
          };

          services.xserver.videoDrivers = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
          };

          environment.systemPackages = lib.mkOption {
            type = lib.types.listOf lib.types.package;
            default = [ ];
          };

          environment.variables = lib.mkOption {
            type = lib.types.attrsOf lib.types.str;
            default = { };
          };

          environment.etc = lib.mkOption {
            type = lib.types.attrsOf lib.types.anything;
            default = { };
          };

          hardware.nvidia = lib.mkOption {
            type = lib.types.attrsOf lib.types.anything;
            default = { };
          };

          hardware.graphics = lib.mkOption {
            type = lib.types.attrsOf lib.types.anything;
            default = { };
          };

          hardware.nvidia-container-toolkit = lib.mkOption {
            type = lib.types.attrsOf lib.types.anything;
            default = { };
          };

          virtualisation.docker.daemon.settings = lib.mkOption {
            type = lib.types.attrsOf lib.types.anything;
            default = { };
          };

          systemd.services = lib.mkOption {
            type = lib.types.attrsOf lib.types.anything;
            default = { };
          };
        };

        config = {
          # Mock nixpkgs with our overlay applied
          _module.args.pkgs = pkgs // {
            nvidia-sdk = pkgs.hello; # Mock SDK package
            nvtop = pkgs.hello; # Mock monitoring
            btop-nvml = pkgs.hello;
            inherit (pkgs) coreutils;
          };

          # Enable our module
          hardware.nvidia-sdk = {
            enable = true;
          };
        };
      }
    ];
  };

  inherit (eval) config;
in
{
  # Test that the module evaluates without errors
  success = true;

  # Test that the module is enabled
  sdkEnabled = config.hardware.nvidia-sdk.enable;

  # Test that NVIDIA driver is in videoDrivers
  hasNvidiaDriver = lib.elem "nvidia" config.services.xserver.videoDrivers;

  # Test that systemPackages is populated (default systemPackages = true)
  hasSystemPackages = (builtins.length config.environment.systemPackages) > 0;

  # Test that environment variables are set
  hasCudaPath = config.environment.variables ? CUDA_PATH;

  # Test that persistenced service is defined (default persistenced = true)
  hasPersistenced = config.systemd.services ? nvidia-persistenced;

  # Test that container toolkit is enabled (default container.enable = true)
  containerEnabled = config.hardware.nvidia-container-toolkit.enable or false;

  # Summary
  summary = {
    enable = config.hardware.nvidia-sdk.enable;
    videoDrivers = config.services.xserver.videoDrivers;
    systemPackages = builtins.length config.environment.systemPackages;
    envVars = builtins.attrNames config.environment.variables;
  };
}
