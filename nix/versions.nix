# nvidia-sdk version configuration
# CUDA 13.3.0 toolkit — Canonical release for SM120 (Blackwell) and SM90 (Hopper)
# Update via: `nix run .#update`
#
# NOTE (toolkit vs container split): the redistributable toolkit below is on
# CUDA 13.3 (2026-05-26 release), but the NGC container (torch + TensorRT-LLM)
# is still built against CUDA 13.1 — NVIDIA has not shipped a 13.3 NGC container
# as of NGC 26.06. This is safe because the NGC python/torch closure bundles its
# own CUDA runtime libs (libcudart/libcublas/libcudnn/libnccl/…) from the
# container and resolves them first on LD_LIBRARY_PATH; the 13.3 toolkit is what
# *user* code (nvcc, cutlass, headers) compiles against. See nix/pkgs/ngc-python.nix.

{
  # ════════════════════════════════════════════════════════════════════════════
  # NGC 26.06 — newest available (torch/TRT-LLM still CUDA 13.1 upstream)
  # ════════════════════════════════════════════════════════════════════════════

  ngc = {
    version = "26.06";
    cuda = "13.3";
    driver = "610.43.02";
    cudnn = "9.23.2.1";
    nccl = "2.30.7";
    tensorrt = "10.15.1.29";
    cutlass = "4.5.2";
    triton = "26.06";
  };

  # ════════════════════════════════════════════════════════════════════════════
  # CUDA 13.3.0 — Current (released 2026-05-26)
  # ════════════════════════════════════════════════════════════════════════════

  cuda = {
    version = "13.3";
    driver = "610.43.02";

    x86_64-linux = {
      url = "https://developer.download.nvidia.com/compute/cuda/13.3.0/local_installers/cuda_13.3.0_610.43.02_linux.run";
      hash = "sha256-X3lIi1f+aTa8laVvm34oOKsvLuMxOxAIlCIG7r4GNS0=";
    };

    aarch64-linux = {
      url = "https://developer.download.nvidia.com/compute/cuda/13.3.0/local_installers/cuda_13.3.0_610.43.02_linux_sbsa.run";
      hash = "sha256-lOxFchl7ZVMtzz0ydGBBfGUn+kLe2dUBDgbduJ6HjUw=";
    };
  };

  cudnn = {
    version = "9.23.2.1";
    x86_64-linux = {
      urls = {
        upstream = "https://developer.download.nvidia.com/compute/cudnn/redist/cudnn/linux-x86_64/cudnn-linux-x86_64-9.23.2.1_cuda13-archive.tar.xz";
      };
      hash = "sha256-WXyqj87H+rzoLDT1qd+pPbQnlUKxfbkvJzkczV1rL8Y=";
    };

    aarch64-linux = {
      urls = {
        upstream = "https://developer.download.nvidia.com/compute/cudnn/redist/cudnn/linux-sbsa/cudnn-linux-sbsa-9.23.2.1_cuda13-archive.tar.xz";
      };
      hash = "sha256-2SzgNs93I3dxs/Zyobpq6yhPmwDOdnehe4pAf+n6NXw=";
    };
  };

  # NCCL: NVIDIA's own redist .txz (top-level nccl_<ver>+cuda13.3_<arch>/{lib,include}).
  # CUDA 13.3 build to match the 13.3 toolkit. Hashes are the live upstream tarballs.
  nccl = {
    version = "2.30.7";

    x86_64-linux = {
      urls = {
        upstream = "https://developer.download.nvidia.com/compute/redist/nccl/v2.30.7/nccl_2.30.7-1+cuda13.3_x86_64.txz";
      };
      hash = "sha256-xkNVh2F4kxpj9/kKmdpirklmzYyapmrN0euhA1nGTHU=";
    };

    aarch64-linux = {
      urls = {
        upstream = "https://developer.download.nvidia.com/compute/redist/nccl/v2.30.7/nccl_2.30.7-1+cuda13.3_aarch64.txz";
      };
      hash = "sha256-7k63tpC60kygfwwiRCOlbHw+Vw+81UrSj1JkMSm3ssI=";
    };
  };

  # TensorRT: latest GA (10.15.1.29). NVIDIA ships it built for cuda-13.1; TRT is
  # forward-compatible within the CUDA 13.x series, so it runs on the 13.3 toolkit.
  tensorrt = {
    version = "10.15.1.29";

    x86_64-linux = {
      urls = {
        upstream = "https://developer.download.nvidia.com/compute/machine-learning/tensorrt/10.15.1/tars/TensorRT-10.15.1.29.Linux.x86_64-gnu.cuda-13.1.tar.gz";
      };

      hash = "sha256-Li1ugAIh6EDh/H66el5LEzkM8UhWtLIa9ClpTiFgIiI=";
    };

    aarch64-linux = {
      urls = {
        upstream = "https://developer.download.nvidia.com/compute/machine-learning/tensorrt/10.15.1/tars/TensorRT-10.15.1.29.Linux.aarch64-gnu.cuda-13.1.tar.gz";
      };

      hash = "sha256-3wwRKk1mvY74kGlyl+AVWNczjVxKyF1AeOgU5Qa9baI=";
    };
  };

  tensorrt-rtx = {
    version = "1.2.0.54";

    # TensorRT-RTX is x86-64 only (no ARM/SBSA support)
    x86_64-linux = {
      urls = {
        upstream = "https://developer.nvidia.com/downloads/tensorrt-rtx-1-2-0-54-linux-x86-64-cuda-13-0-release-external";
      };

      hash = "sha256-qLuPcRaMSJGmGK29e5+AM/06ZOo7DovybBn0chNuDPU=";
    };
  };

  cutensor = {
    version = "2.7.0.5";

    x86_64-linux = {
      urls = {
        upstream = "https://developer.download.nvidia.com/compute/cutensor/redist/libcutensor/linux-x86_64/libcutensor-linux-x86_64-2.7.0.5_cuda13-archive.tar.xz";
      };
      hash = "sha256-jxXICUB1vaEi1B4NHnpT1z/JVVUkhi0XEEYXiiQ0DNQ=";
    };

    aarch64-linux = {
      urls = {
        upstream = "https://developer.download.nvidia.com/compute/cutensor/redist/libcutensor/linux-sbsa/libcutensor-linux-sbsa-2.7.0.5_cuda13-archive.tar.xz";
      };
      hash = "sha256-2BrNdJVSIU667zYGvdQffDc7jD/5UkzHBQpyg3J3eVI=";
    };
  };

  cutlass = {
    version = "4.5.2";
    url = "https://github.com/NVIDIA/cutlass/archive/refs/tags/v4.5.2.zip";
    hash = "sha256-5SMEfoqB2QXRfH5wBwTKKjez0x2zhR8T8EA0bqPMqwM=";
  };

  # ════════════════════════════════════════════════════════════════════════════
  # NGC Container — Triton + TensorRT-LLM (The Standard)
  # ════════════════════════════════════════════════════════════════════════════
  # Multi-arch container (amd64 + arm64)
  #
  # To update hashes:
  #   nix build .#python 2>&1 | grep "got:"
  # Or:
  #   crane export nvcr.io/nvidia/tritonserver:25.12-trtllm-python-py3 - | nix hash file --sri /dev/stdin

  triton-trtllm-container = {
    version = "26.06";

    # Same image ref for both - crane will pull the correct arch.
    # Hashes are recursive-NAR FODs of the extracted rootfs (see
    # nix/modern.nix container-to-nix: `crane export | tar -x`), filled from the
    # build's got-hash, not `nix hash file` of the tar stream.
    x86_64-linux = {
      ref = "nvcr.io/nvidia/tritonserver:26.06-trtllm-python-py3";
      hash = "sha256-cAJ5w2+7RWmVhyDCO+LQTha/tBbjwzCXuRrz0uh5xQM=";
    };

    aarch64-linux = {
      ref = "nvcr.io/nvidia/tritonserver:26.06-trtllm-python-py3";
      # recursive-NAR FOD of the extracted arm64 rootfs, computed on shimmer
      # (aarch64 GB10) — container-to-nix (nix/modern.nix) extracts the host-arch
      # platform, so this must be produced on aarch64-linux.
      hash = "sha256-7FLyt80KGb5nkK9bXtZBnGC4fUAKs11pp/5Fg1qJNjM=";
    };
  };

  # ════════════════════════════════════════════════════════════════════════════
  # Nsight Profiling Tools (bundled with CUDA)
  # ════════════════════════════════════════════════════════════════════════════

  nsight = {
    compute = {
      version = "2026.2.0"; # matches nsight-compute-<ver> dir in the CUDA 13.3 .run
      x86_64-linux.path = "host/linux-desktop-glibc_2_11_3-x64";
      aarch64-linux.path = "host/linux-desktop-t210-a64";
    };

    systems = {
      version = "2026.1.3"; # matches nsight-systems-<ver> dir in the CUDA 13.3 .run
      x86_64-linux.path = "host-linux-x64";
      aarch64-linux.path = "host-linux-armv8";
    };
  };

  # ════════════════════════════════════════════════════════════════════════════
  # SM Architecture Targets (Compute Capabilities)
  # ════════════════════════════════════════════════════════════════════════════
  # Source: https://developer.nvidia.com/cuda-gpus
  #         https://en.wikipedia.org/wiki/CUDA

  sm = {
    # Consumer / Workstation (x86_64)
    turing = "sm_75"; # RTX 20xx, GTX 16xx, Quadro RTX
    ampere = "sm_86"; # RTX 30xx, A-series workstation
    ada = "sm_89"; # RTX 40xx, L4, L40, RTX 6000 Ada
    blackwell-rtx = "sm_120"; # RTX 50xx (x86_64 only)

    # Data Center
    volta = "sm_70"; # V100
    ampere-dc = "sm_80"; # A100, A30
    hopper = "sm_90"; # H100, H200, GH200
    blackwell-dc = "sm_100"; # B100, B200, GB200 (SBSA aarch64)
    blackwell-gb = "sm_121"; # GB12 (SBSA aarch64)

    # Jetson / Tegra
    xavier = "sm_72"; # Jetson AGX Xavier
    orin = "sm_87"; # Jetson Orin
  };

  # ════════════════════════════════════════════════════════════════════════════
  # Driver Versions (for NixOS module)
  # ════════════════════════════════════════════════════════════════════════════

  driver = {
    version = "610.43.02";

    x86_64-linux = {
      url = "https://us.download.nvidia.com/XFree86/Linux-x86_64/610.43.02/NVIDIA-Linux-x86_64-610.43.02.run";
      hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="; # TODO: fetch
    };

    aarch64-linux = {
      url = "https://us.download.nvidia.com/XFree86/Linux-aarch64/610.43.02/NVIDIA-Linux-aarch64-610.43.02.run";
      hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="; # TODO: fetch
    };

    # Open kernel module hashes (Turing+)
    open = {
      x86_64-linux.hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
      aarch64-linux.hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
    };
  };
}
