# nix/versions/cudnn/default.nix — cuDNN Versions
#
# NVIDIA Deep Neural Network library versions.

_:

{
  cudnn = {
    version = "9.17.0.29";

    x86_64-linux = {
      urls = {
        mirror = "https://nvidia-redistributable.weyl.ai/cudnn/cudnn-linux-x86_64-9.17.0.29_cuda13-archive.tar.xz";
        upstream = "https://developer.download.nvidia.com/compute/cudnn/redist/cudnn/linux-x86_64/cudnn-linux-x86_64-9.17.0.29_cuda13-archive.tar.xz";
      };
      hash = "sha256-RV8VB1STyCoaiFCq5hIPP6b35FfL71bByy4KYYtbUJ4=";
    };

    aarch64-linux = {
      urls = {
        mirror = "https://nvidia-redistributable.weyl.ai/cudnn/cudnn-linux-sbsa-9.17.0.29_cuda13-archive.tar.xz";
        upstream = "https://developer.download.nvidia.com/compute/cudnn/redist/cudnn/linux-sbsa/cudnn-linux-sbsa-9.17.0.29_cuda13-archive.tar.xz";
      };
      hash = "sha256-Gb5tjytjpFnmdYGFwej+7d7NtLVnF9xOS7z+MKBhm30=";
    };
  };
}
