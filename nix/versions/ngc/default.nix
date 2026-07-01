# nix/versions/ngc/default.nix — NGC Container Versions
#
# NVIDIA GPU Cloud (NGC) container versions for Triton + TensorRT-LLM.

_:

{
  ngc = {
    version = "25.12";
    cuda = "13.1";
    driver = "590.44.01";
    cudnn = "9.17.0.29";
    nccl = "2.28.9";
    tensorrt = "10.15.1.29";
    cutlass = "4.3.3";
    triton = "25.12";
  };

  # Triton + TensorRT-LLM container (multi-arch)
  triton-trtllm-container = {
    version = "25.12";

    x86_64-linux = {
      ref = "nvcr.io/nvidia/tritonserver:25.12-trtllm-python-py3";
      hash = "sha256-WvHGKXzu1oJk8RRorIDaF9Ii6AuK6eAD7SIWRxs0vkk=";
    };

    aarch64-linux = {
      ref = "nvcr.io/nvidia/tritonserver:25.12-trtllm-python-py3";
      hash = "sha256-9hMiF7lZKLI64EMPQsb924VDG6L3wsTESmEVd85zAAU=";
    };
  };
}
