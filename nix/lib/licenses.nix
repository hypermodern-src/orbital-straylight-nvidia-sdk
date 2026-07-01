# nix/lib/licenses.nix — Custom NVIDIA License Definitions
#
# Defines license metadata for NVIDIA SDK components.
# These are proprietary licenses but redistributable via official redist archives.

_:

{
  nvidiaCuda = {
    shortName = "CUDA";
    fullName = "NVIDIA CUDA Toolkit License";
    url = "https://docs.nvidia.com/cuda/eula/index.html";
    free = false;
    redistributable = true;
  };

  nvidiaCudnn = {
    shortName = "cuDNN";
    fullName = "NVIDIA cuDNN Software License Agreement";
    url = "https://docs.nvidia.com/deeplearning/cudnn/latest/reference/eula.html";
    free = false;
    redistributable = true;
  };

  nvidiaTensorrt = {
    shortName = "TensorRT";
    fullName = "NVIDIA TensorRT Software License Agreement";
    url = "https://docs.nvidia.com/deeplearning/tensorrt/sla/index.html";
    free = false;
    redistributable = true;
  };

  nvidiaCutensor = {
    shortName = "cuTENSOR";
    fullName = "NVIDIA cuTENSOR Software License Agreement";
    url = "https://docs.nvidia.com/cuda/cutensor/latest/license.html";
    free = false;
    redistributable = true;
  };
}
