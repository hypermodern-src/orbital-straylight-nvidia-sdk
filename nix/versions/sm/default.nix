# nix/versions/sm/default.nix — SM Architecture Targets
#
# NVIDIA GPU Streaming Multiprocessor architecture targets (compute capabilities).
# Source: https://developer.nvidia.com/cuda-gpus
#         https://en.wikipedia.org/wiki/CUDA

_:

{
  sm = {
    # Consumer / Workstation
    turing = "sm_75"; # RTX 20xx, GTX 16xx, Quadro RTX
    ampere = "sm_86"; # RTX 30xx, A-series workstation
    ada = "sm_89"; # RTX 40xx, L4, L40, RTX 6000 Ada
    blackwell-rtx = "sm_120"; # RTX 50xx

    # Data Center
    volta = "sm_70"; # V100
    ampere-dc = "sm_80"; # A100, A30
    hopper = "sm_90"; # H100, H200, GH200
    blackwell = "sm_100"; # B100, B200, GB200

    # Jetson / Tegra
    xavier = "sm_72"; # Jetson AGX Xavier
    orin = "sm_87"; # Jetson Orin
  };
}
