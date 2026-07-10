# nvidia-sdk.nix — NixOS Module
#
# Provides declarative NVIDIA driver + CUDA SDK configuration.
#
# Usage:
#   hardware.nvidia-sdk.enable = true;

{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.hardware.nvidia-sdk;
  versions = import ../versions.nix;

in
{
  _class = "nixos";

  options.hardware.nvidia-sdk = {
    enable = lib.mkEnableOption "NVIDIA SDK with driver management";

    # ══════════════════════════════════════════════════════════════════════════
    # Driver
    # ══════════════════════════════════════════════════════════════════════════

    driver = {
      package = lib.mkOption {
        type = lib.types.package;
        default = config.boot.kernelPackages.nvidiaPackages.latest;
        defaultText = lib.literalExpression "config.boot.kernelPackages.nvidiaPackages.latest";
        description = "The NVIDIA driver package to use.";
      };

      open = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Use open-source kernel modules (Turing+ required).";
      };
    };

    # ══════════════════════════════════════════════════════════════════════════
    # Exposure
    # ══════════════════════════════════════════════════════════════════════════

    systemPackages = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Add nvidia-sdk to environment.systemPackages.";
    };

    monitoring = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Install GPU monitoring tools (nvtop, btop with NVML).";
    };

    # ══════════════════════════════════════════════════════════════════════════
    # Container Runtime
    # ══════════════════════════════════════════════════════════════════════════

    container = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable NVIDIA Container Toolkit for Docker/Podman.";
      };
    };

    # ══════════════════════════════════════════════════════════════════════════
    # Persistence Daemon
    # ══════════════════════════════════════════════════════════════════════════

    persistenced = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Enable nvidia-persistenced for headless/server workloads.
        Keeps GPU initialized without X11/Wayland.
      '';
    };
  };

  # ════════════════════════════════════════════════════════════════════════════
  # IMPLEMENTATION
  # ════════════════════════════════════════════════════════════════════════════

  config = lib.mkIf cfg.enable {

    # ──────────────────────────────────────────────────────────────────────────
    # Driver
    # ──────────────────────────────────────────────────────────────────────────

    services.xserver.videoDrivers = [ "nvidia" ];

    hardware.nvidia = {
      package = cfg.driver.package;
      open = cfg.driver.open;
      modesetting.enable = true;
      nvidiaSettings = true;
    };

    hardware.graphics = {
      enable = true;
      enable32Bit = true;
    };

    # ──────────────────────────────────────────────────────────────────────────
    # System Packages
    # ──────────────────────────────────────────────────────────────────────────

    environment.systemPackages = lib.mkMerge [
      (lib.mkIf cfg.systemPackages [ pkgs.nvidia-sdk ])
      (lib.mkIf cfg.monitoring [
        pkgs.nvtop
        pkgs.btop-nvml
      ])
    ];

    # ──────────────────────────────────────────────────────────────────────────
    # Environment Variables
    # ──────────────────────────────────────────────────────────────────────────

    environment.variables = lib.mkIf cfg.systemPackages {
      CUDA_PATH = "${pkgs.nvidia-sdk}";
      CUDA_HOME = "${pkgs.nvidia-sdk}";
    };

    # ──────────────────────────────────────────────────────────────────────────
    # Container Runtime
    # ──────────────────────────────────────────────────────────────────────────

    hardware.nvidia-container-toolkit.enable = cfg.container.enable;

    virtualisation.docker.daemon.settings = lib.mkIf cfg.container.enable { features.cdi = true; };

    # ──────────────────────────────────────────────────────────────────────────
    # Persistence Daemon
    # ──────────────────────────────────────────────────────────────────────────

    users.users.nvidia-persistenced = lib.mkIf cfg.persistenced {
      isSystemUser = true;
      group = "nvidia-persistenced";
      description = "NVIDIA Persistence Daemon user";
    };

    users.groups.nvidia-persistenced = lib.mkIf cfg.persistenced { };

    systemd.services.nvidia-persistenced = lib.mkIf cfg.persistenced {
      description = "NVIDIA Persistence Daemon";
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "forking";
        Restart = "always";
        PIDFile = "/run/nvidia-persistenced/nvidia-persistenced.pid";
        ExecStart = "${cfg.driver.package.persistenced}/bin/nvidia-persistenced --user nvidia-persistenced --persistence-mode --verbose";
        ExecStopPost = "${pkgs.coreutils}/bin/rm -rf /run/nvidia-persistenced";
        RuntimeDirectory = "nvidia-persistenced";
        RuntimeDirectoryMode = "0755";
      };
    };

    # ──────────────────────────────────────────────────────────────────────────
    # Metadata
    # ──────────────────────────────────────────────────────────────────────────

    environment.etc."nvidia-sdk-version".text = ''
      NVIDIA SDK: ${pkgs.nvidia-sdk.version or versions.cuda.version}
      Driver: ${cfg.driver.package.version or "unknown"}
      NGC: ${versions.ngc.version}
    '';
  };
}
