# nix/versions/tensorrt/default.nix — TensorRT Versions
#
# NVIDIA TensorRT inference optimization library versions.

_:

{
  tensorrt = {
    version = "10.15.1.29";

    x86_64-linux = {
      urls = {
        mirror = "https://nvidia-redistributable.weyl.ai/TensorRT-10.15.1.29.Linux.x86_64-gnu.cuda-13.1.tar.gz";
        upstream = "https://developer.download.nvidia.com/compute/machine-learning/tensorrt/10.15.1/tars/TensorRT-10.15.1.29.Linux.x86_64-gnu.cuda-13.1.tar.gz";
      };
      hash = "sha256-Li1ugAIh6EDh/H66el5LEzkM8UhWtLIa9ClpTiFgIiI=";
    };

    aarch64-linux = {
      urls = {
        mirror = "https://nvidia-redistributable.weyl.ai/TensorRT-10.15.1.29.Linux.aarch64-gnu.cuda-13.1.tar.gz";
        upstream = "https://developer.download.nvidia.com/compute/machine-learning/tensorrt/10.15.1/tars/TensorRT-10.15.1.29.Linux.aarch64-gnu.cuda-13.1.tar.gz";
      };
      hash = "sha256-3wwRKk1mvY74kGlyl+AVWNczjVxKyF1AeOgU5Qa9baI=";
    };
  };
}
