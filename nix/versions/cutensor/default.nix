# nix/versions/cutensor/default.nix — cuTENSOR Versions
#
# NVIDIA cuTENSOR high-performance tensor library versions.

_:

{
  cutensor = {
    version = "2.4.1.4";

    x86_64-linux = {
      urls = {
        mirror = "https://nvidia-redistributable.weyl.ai/libcutensor/libcutensor-linux-x86_64-2.4.1.4_cuda13-archive.tar.xz";
        upstream = "https://developer.download.nvidia.com/compute/cutensor/redist/libcutensor/linux-x86_64/libcutensor-linux-x86_64-2.4.1.4_cuda13-archive.tar.xz";
      };
      hash = "sha256-IfsKmjt7ZmMiNme1h/KrHFTkphyXX+oPnU9W2cM/Mf4=";
    };

    aarch64-linux = {
      urls = {
        mirror = "https://nvidia-redistributable.weyl.ai/libcutensor/libcutensor-linux-sbsa-2.4.1.4_cuda13-archive.tar.xz";
        upstream = "https://developer.download.nvidia.com/compute/cutensor/redist/libcutensor/linux-sbsa/libcutensor-linux-sbsa-2.4.1.4_cuda13-archive.tar.xz";
      };
      hash = "sha256-m6/9Nli39NotL5TSPDrN220SximX09o5p3SgWP7wSqU=";
    };
  };
}
