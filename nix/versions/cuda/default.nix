# nix/versions/cuda/default.nix — CUDA Toolkit Versions
#
# Defines all supported CUDA toolkit versions with their
# download URLs, hashes, and driver requirements.

_:

{
  cuda = {
    # Current default version
    version = "13.1";
    driver = "590.44.01";

    # x86_64-linux
    x86_64-linux = {
      url = "https://developer.download.nvidia.com/compute/cuda/13.1.0/local_installers/cuda_13.1.0_590.44.01_linux.run";
      hash = "sha256-a0/fJpSz16+8Um8mQStM9PBQsgIyRFUFMwcxD1OzI6c=";
    };

    # aarch64-linux (SBSA)
    aarch64-linux = {
      url = "https://developer.download.nvidia.com/compute/cuda/13.1.0/local_installers/cuda_13.1.0_590.44.01_linux_sbsa.run";
      hash = "sha256-Bs2kmnAxscmfeEI3vlyFJhk3nLupVVA2BFBEud3JkkA=";
    };
  };
}
