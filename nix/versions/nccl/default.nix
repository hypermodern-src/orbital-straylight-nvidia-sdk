# nix/versions/nccl/default.nix — NCCL Versions
#
# NVIDIA Collective Communications Library versions.

_:

{
  nccl = {
    version = "2.28.9";

    x86_64-linux = {
      urls = {
        mirror = "https://nvidia-redistributable.weyl.ai/nccl/nccl_2.28.9-1+cuda12.0_x86_64.txz";
        upstream = "https://files.pythonhosted.org/packages/4a/4e/44dbb46b3d1b0ec61afda8e84837870f2f9ace33c564317d59b70bc19d3e/nvidia_nccl_cu12-2.28.9-py3-none-manylinux_2_18_x86_64.whl";
      };
      hash = "sha256-Ta9tHpdQVel+xb22iGc+A2OwYSnAiT2UtdVNLs1zDTw=";
    };

    aarch64-linux = {
      urls = {
        mirror = "https://nvidia-redistributable.weyl.ai/nccl/nccl_2.28.9-1+cuda12.0_aarch64.txz";
        upstream = "https://files.pythonhosted.org/packages/08/c4/120d2dfd92dff2c776d68f361ff8705fdea2ca64e20b612fab0fd3f581ac/nvidia_nccl_cu12-2.28.9-py3-none-manylinux_2_18_aarch64.whl";
      };
      hash = "sha256-ubC3CGU4LFA7bLIz3RPkKJSh1dDA9oMSSgkFkpeQxzs=";
    };
  };
}
