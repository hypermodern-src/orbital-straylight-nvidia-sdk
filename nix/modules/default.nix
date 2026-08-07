{ inputs, ... }: {

  imports = [ ./fmt.nix ];

  perSystem =
    { system, ... }:
    let
      versions = import ../versions.nix;

      # Import nixpkgs with unfree + CUDA config
      pkgs = import inputs.nixpkgs {
        inherit system;

        config = {
          allowUnfree = true;
          cudaSupport = true;
        };
      };

      # ════════════════════════════════════════════════════════════════════
      # PLATFORM (shared via nix/lib/platform.nix)
      # ════════════════════════════════════════════════════════════════════

      inherit (pkgs) lib stdenv;

      platform = import ../lib/platform.nix {
        inherit lib stdenv;
        inherit (pkgs) gcc15;
      };

      # ════════════════════════════════════════════════════════════════════
      # LLVM-GIT (SM120 support)
      # ════════════════════════════════════════════════════════════════════

      llvm-git = pkgs.callPackage ../pkgs/llvm-git.nix { llvm-project-src = inputs.llvm-project; };

      # ════════════════════════════════════════════════════════════════════
      # CUDA STDENV — The One True Toolchain
      # ════════════════════════════════════════════════════════════════════

      cudaStdenv = platform.mkCudaStdenv {
        inherit (pkgs) wrapCCWith stdenvAdapters glibc;
        inherit llvm-git cuda-merged;
        inherit (pkgs) gcc15Stdenv;
        ccLib = stdenv.cc.cc.lib;
        gcc15Pkg = pkgs.gcc15;
      };

      # ════════════════════════════════════════════════════════════════════
      # MODERN PRIMITIVES
      # ════════════════════════════════════════════════════════════════════

      inherit ((import ../modern.nix pkgs pkgs)) modern;

      # ════════════════════════════════════════════════════════════════════
      # CUDA COMPONENTS
      # ════════════════════════════════════════════════════════════════════

      cuda = pkgs.callPackage ../pkgs/cuda.nix { inherit versions; };

      # The driver pinned to match the CUDA toolkit (versions.driver.version).
      # Built against the default nixpkgs kernel here so it is a standalone,
      # CI-buildable artifact; the NixOS module rebuilds it for the running
      # kernel via config.boot.kernelPackages.
      nvidia-driver = pkgs.callPackage ../pkgs/nvidia-driver.nix {
        inherit versions;
        nvidiaPackages = pkgs.linuxPackages.nvidiaPackages;
      };

      cuda-merged = pkgs.symlinkJoin {
        name = "cuda-${cuda.version}-merged";
        paths = [ cuda ];
        postBuild = ''
          if [ -d $out/lib64 ] && [ ! -e $out/lib ]; then
            ln -s lib64 $out/lib
          fi
        '';
      };

      cudnn = pkgs.callPackage ../pkgs/cudnn.nix {
        inherit versions;
        extract = modern;
        inherit cuda;
      };

      nccl = pkgs.callPackage ../pkgs/nccl.nix {
        inherit versions;
        inherit cuda;
      };

      tensorrt = pkgs.callPackage ../pkgs/tensorrt.nix {
        inherit versions;
        extract = modern;
        inherit cuda;
        inherit cudnn;
        inherit nccl;
      };

      cutensor = pkgs.callPackage ../pkgs/cutensor.nix {
        inherit versions;
        extract = modern;
        inherit cuda;
      };

      cutlass = pkgs.callPackage ../pkgs/cutlass.nix {
        inherit versions;
        inherit cuda;
      };

      nvidia-sdk = pkgs.callPackage ../pkgs/nvidia-sdk.nix {
        inherit
          versions
          modern
          cuda
          cudnn
          nccl
          tensorrt
          cutlass
          cutensor
          ;
      };

      # ════════════════════════════════════════════════════════════════════
      # NGC CONTAINER — Single Source of Truth
      # ════════════════════════════════════════════════════════════════════

      ngcContainer = modern.container-to-nix {
        name = "ngc-${versions.ngc.version}-rootfs";
        imageRef = versions.triton-trtllm-container.${system}.ref;
        hash = versions.triton-trtllm-container.${system}.hash;
      };

      # vLLM container — provides vllm backend + vllm Python package
      vllmContainer = modern.container-to-nix {
        name = "vllm-${versions.ngc.version}-rootfs";
        imageRef = versions.triton-vllm-container.${system}.ref;
        hash = versions.triton-vllm-container.${system}.hash;
      };

      tritonserver = pkgs.callPackage ../pkgs/tritonserver.nix {
        inherit versions modern nvidia-sdk;
        containerSrc = ngcContainer;
        vllmContainerSrc = vllmContainer;
        backend = "trtllm";
      };

      # Native TensorRT-LLM path without the unrelated vLLM container closure.
      # This is the base for K3 expert paging and the Triton OpenAI frontend.
      tritonserver-trtllm = pkgs.callPackage ../pkgs/tritonserver.nix {
        inherit versions modern nvidia-sdk;
        containerSrc = ngcContainer;
        backend = "trtllm";
      };

      # ════════════════════════════════════════════════════════════════════
      # PYTHON 3.12 — NGC environments (two variants due to torch incompatibility)
      # ════════════════════════════════════════════════════════════════════
      #
      # TRT-LLM and vLLM containers have incompatible torch versions:
      #   - TRT-LLM: torch 2.10.0a0 (nv25.12)
      #   - vLLM: torch 2.13.0a0 (nv26.6)
      #
      # We expose both as separate packages. Default 'python' is TRT-LLM
      # since it's the primary use case for this SDK.

      python-trtllm = pkgs.callPackage ../pkgs/ngc-python.nix {
        containerSrc = ngcContainer;
        inherit nvidia-sdk modern;
        variant = "trtllm";
      };

      python-vllm = pkgs.callPackage ../pkgs/ngc-python.nix {
        containerSrc = vllmContainer;
        inherit nvidia-sdk modern;
        variant = "vllm";
      };

      # Default python is TRT-LLM (primary use case)
      python = python-trtllm;

      # libtorch C++ library extracted from NGC python torch
      # Enables hasktorch on aarch64-linux with GPU support
      libtorch-bin = pkgs.callPackage ../pkgs/libtorch.nix { python = python-trtllm; };

      # ════════════════════════════════════════════════════════════════════
      # VALIDATION & SAMPLES
      # ════════════════════════════════════════════════════════════════════

      cuda-samples = pkgs.callPackage ../pkgs/cuda-samples.nix {
        inherit versions;
        inherit cuda;
      };

      nccl-tests = pkgs.callPackage ../pkgs/nccl-tests.nix {
        inherit cuda;
        inherit nccl;
      };

      validate-sdk = pkgs.callPackage ../pkgs/validate-sdk.nix { inherit nvidia-sdk; };

      # ════════════════════════════════════════════════════════════════════
      # MONITORING & PROFILING
      # ════════════════════════════════════════════════════════════════════

      monitoring = pkgs.callPackage ../pkgs/monitoring-tools.nix { inherit cuda; };

      # Nsight GUI apps (profilers)
      nsight-gui-apps = pkgs.callPackage ../pkgs/nsight-gui-apps.nix { inherit versions nvidia-sdk; };

      agenix = inputs.agenix.packages.${system}.default;

    in
    {
      packages = {
        default = nvidia-sdk;
        inherit
          nvidia-sdk
          cuda
          nvidia-driver
          cudnn
          nccl
          tensorrt
          cutensor
          cutlass
          cuda-merged
          tritonserver
          tritonserver-trtllm
          python
          python-trtllm
          python-vllm
          libtorch-bin
          cuda-samples
          nccl-tests
          validate-sdk
          llvm-git
          cudaStdenv
          ;

        # Raw NGC container rootfs — useful for browsing available libs
        ngc-rootfs = ngcContainer;

        inherit (monitoring) nvtop;
        inherit (monitoring) btop;

        # Nsight profiling tools
        inherit nsight-gui-apps;
      };

      devShells.default = pkgs.mkShell {
        packages = [
          nvidia-sdk
          python
          agenix
        ];

        shellHook = ''
          echo "nvidia-sdk — CUDA ${versions.cuda.version} — NGC ${versions.ngc.version}"
          echo "Complete Python environment from NGC container"
          echo ""
          export LD_LIBRARY_PATH="${nvidia-sdk}/lib64:/run/opengl-driver/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
          export CUDA_PATH="${nvidia-sdk}"
          export CUDA_HOME="${nvidia-sdk}"
        '';
      };

      checks = {
        # ── SDK structure ──────────────────────────────────────────────
        # Verifies the merged nvidia-sdk has headers, libraries,
        # setup-hook env vars, pkg-config, and version metadata.
        sdk-structure =
          pkgs.runCommand "check-sdk-structure"
            {
              nativeBuildInputs = [
                nvidia-sdk
                pkgs.pkg-config
              ];
            }
            ''
              echo "=== SDK structure check ==="

              # setup-hook must set CUDA_PATH
              test -n "$CUDA_PATH" || (echo "FAIL: CUDA_PATH not set by setup-hook" && exit 1)
              echo "ok: CUDA_PATH=$CUDA_PATH"

              # Headers
              test -d "$CUDA_PATH/include" || (echo "FAIL: include/ missing" && exit 1)
              for hdr in cuda.h cudnn.h nccl.h NvInfer.h cutensor.h; do
                test -f "$CUDA_PATH/include/$hdr" || (echo "FAIL: $hdr missing" && exit 1)
              done
              echo "ok: headers present"

              # Core libraries
              for lib in cudart cublas cufft curand cusolver cusparse nvrtc cudnn nccl nvinfer cutensor; do
                ls "$CUDA_PATH/lib64/lib$lib"*.so* >/dev/null 2>&1 || (echo "FAIL: lib$lib.so missing" && exit 1)
              done
              echo "ok: core libraries present"

              # Key binaries
              for bin in nvcc ptxas fatbinary nvlink; do
                test -x "$CUDA_PATH/bin/$bin" || (echo "FAIL: $bin missing" && exit 1)
              done
              echo "ok: core binaries present"

              # pkg-config
              pkg-config --validate nvidia-sdk || (echo "FAIL: nvidia-sdk.pc invalid" && exit 1)
              echo "ok: pkg-config valid"

              # version.json
              test -f "$CUDA_PATH/version.json" || (echo "FAIL: version.json missing" && exit 1)
              echo "ok: version.json present"

              # validate script
              test -x "$CUDA_PATH/bin/nvidia-sdk-validate" || (echo "FAIL: nvidia-sdk-validate missing" && exit 1)
              echo "ok: nvidia-sdk-validate present"

              echo "=== SDK structure: PASS ===" > $out
            '';

        # ── Version consistency ────────────────────────────────────────
        # Verifies that version.json inside the built SDK matches
        # the versions declared in nix/versions.nix.
        version-consistency =
          pkgs.runCommand "check-version-consistency"
            {
              nativeBuildInputs = [
                nvidia-sdk
                pkgs.jq
              ];
            }
            ''
              echo "=== Version consistency check ==="

              json="$CUDA_PATH/version.json"
              test -f "$json" || (echo "FAIL: version.json missing" && exit 1)

              check() {
                local key="$1" expected="$2"
                actual=$(${pkgs.jq}/bin/jq -r ".$key" "$json")
                if [ "$actual" != "$expected" ]; then
                  echo "FAIL: $key: expected '$expected', got '$actual'"
                  exit 1
                fi
                echo "ok: $key=$actual"
              }

              check cuda     "${versions.cuda.version}"
              check cudnn    "${versions.cudnn.version}"
              check nccl     "${versions.nccl.version}"
              check tensorrt "${versions.tensorrt.version}"
              check cutlass  "${versions.cutlass.version}"
              check cutensor "${versions.cutensor.version}"

              echo "=== Version consistency: PASS ===" > $out
            '';

        # ── LLVM NVPTX target ─────────────────────────────────────────
        # Verifies the custom LLVM build supports the NVPTX backend
        # (required for CUDA compilation via clang).
        llvm-nvptx = pkgs.runCommand "check-llvm-nvptx" { } ''
          ${llvm-git}/bin/clang --print-targets | ${pkgs.gnugrep}/bin/grep -iq nvptx \
            || (echo "FAIL: NVPTX target missing from LLVM" && exit 1)
          echo "ok: LLVM has NVPTX target" > $out
        '';

        # ── Individual package structure ──────────────────────────────
        # Spot-checks that individual component packages have the
        # expected directories/files (catches broken extractions).
        component-structure = pkgs.runCommand "check-component-structure" { } ''
          echo "=== Component structure check ==="

          # cuDNN
          test -f "${cudnn}/lib/libcudnn.so" || test -d "${cudnn}/lib" \
            || (echo "FAIL: cudnn lib/ missing" && exit 1)
          test -f "${cudnn}/include/cudnn.h" \
            || (echo "FAIL: cudnn headers missing" && exit 1)
          echo "ok: cudnn"

          # NCCL
          test -f "${nccl}/lib/libnccl.so" \
            || (echo "FAIL: nccl lib missing" && exit 1)
          test -f "${nccl}/include/nccl.h" \
            || (echo "FAIL: nccl headers missing" && exit 1)
          echo "ok: nccl"

          # TensorRT
          test -f "${tensorrt}/lib/libnvinfer.so" \
            || (echo "FAIL: tensorrt lib missing" && exit 1)
          test -f "${tensorrt}/include/NvInfer.h" \
            || (echo "FAIL: tensorrt headers missing" && exit 1)
          echo "ok: tensorrt"

          # cuTensor
          test -f "${cutensor}/lib/libcutensor.so" || ls "${cutensor}/lib"/libcutensor*.so* >/dev/null 2>&1 \
            || (echo "FAIL: cutensor lib missing" && exit 1)
          echo "ok: cutensor"

          # CUTLASS (header-only)
          test -d "${cutlass}/include/cutlass" \
            || (echo "FAIL: cutlass headers missing" && exit 1)
          echo "ok: cutlass"

          echo "=== Component structure: PASS ===" > $out
        '';

        # ── Setup-hook env vars ───────────────────────────────────────
        # Verifies the setup-hook correctly exports all expected vars.
        setup-hook = pkgs.runCommand "check-setup-hook" { nativeBuildInputs = [ nvidia-sdk ]; } ''
          echo "=== Setup-hook check ==="
          for var in CUDA_PATH CUDA_HOME CUDNN_HOME TENSORRT_HOME; do
            eval "val=\$$var"
            test -n "$val" || (echo "FAIL: $var not set" && exit 1)
            echo "ok: $var=$val"
          done
          echo "=== Setup-hook: PASS ===" > $out
        '';

        # ── Nsight tools ──────────────────────────────────────────────
        # Verifies Nsight Compute and Systems directories exist in
        # the SDK, and that the CLI wrappers (ncu, nsys) are present.
        nsight-tools = pkgs.runCommand "check-nsight-tools" { nativeBuildInputs = [ nvidia-sdk ]; } ''
          echo "=== Nsight tools check ==="

          ncuDir="$CUDA_PATH/nsight-compute-${versions.nsight.compute.version}"
          nsysDir="$CUDA_PATH/nsight-systems-${versions.nsight.systems.version}"

          # Nsight Compute directory
          test -d "$ncuDir" || (echo "FAIL: $ncuDir missing" && exit 1)
          echo "ok: nsight-compute directory exists"

          # Nsight Systems directory
          test -d "$nsysDir" || (echo "FAIL: $nsysDir missing" && exit 1)
          echo "ok: nsight-systems directory exists"

          # CLI wrappers
          test -x "$CUDA_PATH/bin/ncu"  || (echo "FAIL: ncu binary missing" && exit 1)
          echo "ok: ncu binary present"

          test -x "$CUDA_PATH/bin/nsys" || (echo "FAIL: nsys binary missing" && exit 1)
          echo "ok: nsys binary present"

          # Host binaries in arch-specific paths
          ncuHost="$ncuDir/${versions.nsight.compute.${system}.path}"
          test -d "$ncuHost" || (echo "FAIL: ncu host dir missing: $ncuHost" && exit 1)
          echo "ok: ncu host path exists ($ncuHost)"

          nsysHost="$nsysDir/${versions.nsight.systems.${system}.path}"
          test -d "$nsysHost" || (echo "FAIL: nsys host dir missing: $nsysHost" && exit 1)
          echo "ok: nsys host path exists ($nsysHost)"

          echo "=== Nsight tools: PASS ===" > $out
        '';

        # ── Platform arch consistency ─────────────────────────────────
        # Verifies that the platform helper produces a valid cudaArch
        # for the current system.
        platform-arch = pkgs.runCommand "check-platform-arch" { } ''
          echo "=== Platform arch check ==="
          arch="${platform.cudaArch}"
          case "$arch" in
            sm_100|sm_120|sm_121)
              echo "ok: cudaArch=$arch"
              ;;
            *)
              echo "FAIL: unexpected cudaArch=$arch"
              exit 1
              ;;
          esac
          echo "=== Platform arch: PASS ===" > $out
        '';

        # ── Python imports (NGC packages) ─────────────────────────────
        python-imports =
          pkgs.runCommand "check-python-imports"
            {
              nativeBuildInputs = [ python ];
              LD_LIBRARY_PATH = "${nvidia-sdk}/lib64";
            }
            ''
              export HOME=$(mktemp -d)
              ${python}/bin/python3 -c "
              import sys
              print('Python:', sys.version)
              import numpy; print('numpy:', numpy.__version__)
              import torch; print('torch:', torch.__version__)
              print('CUDA available:', torch.cuda.is_available())
              "
              echo "Python imports: ok" > $out
            '';

        # ── TensorRT-LLM/Triton OpenAI surface ──────────────────────
        # This intentionally uses the TRT-LLM-only closure. It proves the NGC
        # LLMAPI repository template and frontend wrapper survive extraction
        # and patching without importing the unrelated vLLM image.
        triton-trtllm-structure =
          pkgs.runCommand "check-triton-trtllm-structure" { nativeBuildInputs = [ pkgs.gnugrep ]; }
            ''
              root=${tritonserver-trtllm}
              test -x "$root/bin/tritonserver"
              test -x "$root/bin/triton-openai"
              test ! -d "$root/backends/vllm"
              test -f "$root/python/openai/types/__init__.py"
              test -e "$root/lib/libnvshmem_host.so.3"
              grep -F 'LD_PRELOAD' "$root/bin/triton-openai" >/dev/null
              ! grep -F 'LD_LIBRARY_PATH' "$root/bin/triton-openai"
              grep -F "$root/backends" "$root/python/tritonserver/_api/_server.py" >/dev/null
              ! grep -F '/opt/tritonserver' "$root/python/tritonserver/_api/_server.py"
              test "$(grep -c -F 'include_usage = True' \
                "$root/python/openai/openai_frontend/engine/triton_engine.py")" -eq 2
              ! grep -F 'include_usage = request.stream_options' \
                "$root/python/openai/openai_frontend/engine/triton_engine.py"
              test -f "$root/share/tritonserver/model-repositories/llmapi/tensorrt_llm/config.pbtxt"
              test -f "$root/share/tritonserver/model-repositories/llmapi/tensorrt_llm/1/model.py"
              test -f "$root/share/tritonserver/model-repositories/llmapi/tensorrt_llm/1/model.yaml"
              grep -F 'backend: "python"' \
                "$root/share/tritonserver/model-repositories/llmapi/tensorrt_llm/config.pbtxt" >/dev/null
              "$root/bin/triton-openai" --help >help.txt
              grep -F -- '--openai-port' help.txt >/dev/null

              mkdir -p "$out"
              cp help.txt "$out/"
              printf '%s\n' ${lib.escapeShellArg versions.triton-trtllm-container.version} >"$out/triton-version"
            '';

        # ── Ignore-list sync ──────────────────────────────────────────
        # Ensures autoPatchelfIgnoreMissingDeps and verify-closure ignore
        # lists are in sync across all packages. Without this, a library
        # ignored by autoPatchelf but not by verify-closure will cause a
        # MODE2 dangling failure at build time (discovered too late).
        ignore-sync =
          pkgs.runCommand "check-ignore-sync"
            {
              nativeBuildInputs = [
                pkgs.bash
                pkgs.gnused
                pkgs.gnugrep
              ];
            }
            ''
              ${pkgs.bash}/bin/sh ${../scripts/check-ignore-sync.sh} "${./.}"
              echo "ok: ignore lists in sync" > $out
            '';
      };

      apps = {
        tritonserver = {
          type = "app";
          program = "${tritonserver}/bin/tritonserver";
          meta.description = "NVIDIA Triton Inference Server";
        };

        triton-openai = {
          type = "app";
          program = "${tritonserver-trtllm}/bin/triton-openai";
          meta.description = "Triton with the OpenAI-compatible frontend";
        };

        # TensorRT-LLM CLI tools
        trtllm-bench = {
          type = "app";
          program = "${python}/bin/trtllm-bench";
          meta.description = "TensorRT-LLM benchmarking tool";
        };

        trtllm-build = {
          type = "app";
          program = "${python}/bin/trtllm-build";
          meta.description = "TensorRT-LLM engine builder";
        };

        trtllm-serve = {
          type = "app";
          program = "${python}/bin/trtllm-serve";
          meta.description = "TensorRT-LLM inference server";
        };

        torchrun = {
          type = "app";
          program = "${python}/bin/torchrun";
          meta.description = "PyTorch distributed training launcher";
        };

        # Nsight profilers (CLI)
        ncu = {
          type = "app";
          program = "${nvidia-sdk}/bin/ncu";
          meta.description = "NVIDIA Nsight Compute (CLI)";
        };

        nsys = {
          type = "app";
          program = "${nvidia-sdk}/bin/nsys";
          meta.description = "NVIDIA Nsight Systems (CLI)";
        };

        # Nsight profilers (GUI)
        ncu-ui = {
          type = "app";
          program = "${nsight-gui-apps}/bin/ncu-ui";
          meta.description = "NVIDIA Nsight Compute (GUI)";
        };

        nsys-ui = {
          type = "app";
          program = "${nsight-gui-apps}/bin/nsys-ui";
          meta.description = "NVIDIA Nsight Systems (GUI)";
        };

        # Monitoring
        nvtop = {
          type = "app";
          program = "${monitoring.nvtop}/bin/nvtop";
          meta.description = "GPU process monitor";
        };

        btop = {
          type = "app";
          program = "${monitoring.btop}/bin/btop";
          meta.description = "System monitor with GPU support";
        };
      };
    };

  flake = {
    overlays.default =
      final: prev:
      let
        versions = import ../versions.nix;
        inherit ((import ../modern.nix final prev)) modern;

        inherit (final) lib stdenv;
        platform = import ../lib/platform.nix {
          inherit lib stdenv;
          inherit (final) gcc15;
        };
      in
      {
        inherit modern;

        llvm-git = final.callPackage ../pkgs/llvm-git.nix { llvm-project-src = inputs.llvm-project; };

        cuda = final.callPackage ../pkgs/cuda.nix { inherit versions; };

        cuda-merged = prev.symlinkJoin {
          name = "cuda-${final.cuda.version}-merged";
          paths = [ final.cuda ];
          postBuild = ''
            if [ -d $out/lib64 ] && [ ! -e $out/lib ]; then
              ln -s lib64 $out/lib
            fi
          '';
        };

        cudaStdenv = platform.mkCudaStdenv {
          inherit (final) wrapCCWith stdenvAdapters glibc;
          inherit (final) llvm-git;
          inherit (final) cuda-merged;
          inherit (final) gcc15Stdenv;
          ccLib = final.stdenv.cc.cc.lib;
          gcc15Pkg = final.gcc15;
        };

        cudnn = final.callPackage ../pkgs/cudnn.nix {
          inherit versions;
          extract = modern;
          inherit (final) cuda;
        };

        nccl = final.callPackage ../pkgs/nccl.nix {
          inherit versions;
          inherit (final) cuda;
        };

        tensorrt = final.callPackage ../pkgs/tensorrt.nix {
          inherit versions;
          extract = modern;
          inherit (final) cuda;
          inherit (final) cudnn;
          inherit (final) nccl;
        };

        cutensor = final.callPackage ../pkgs/cutensor.nix {
          inherit versions;
          extract = modern;
          inherit (final) cuda;
        };

        cutlass = final.callPackage ../pkgs/cutlass.nix {
          inherit versions;
          inherit (final) cuda;
        };

        nvidia-sdk = final.callPackage ../pkgs/nvidia-sdk.nix {
          inherit versions;
          inherit (final) cuda;
          inherit (final) cudnn;
          inherit (final) nccl;
          inherit (final) tensorrt;
          inherit (final) cutlass;
          inherit (final) cutensor;
        };

        tritonserver =
          let
            container = modern.container-to-nix {
              name = "ngc-${versions.ngc.version}-rootfs";
              imageRef = versions.triton-trtllm-container.${stdenv.hostPlatform.system}.ref;
              hash = versions.triton-trtllm-container.${stdenv.hostPlatform.system}.hash;
            };
          in
          final.callPackage ../pkgs/tritonserver.nix {
            inherit versions modern;
            inherit (final) nvidia-sdk;
            containerSrc = container;
            backend = "trtllm";
          };

        # Python with complete NGC packages (torch, triton, tensorrt_llm, numpy, etc.)
        python =
          let
            container = modern.container-to-nix {
              name = "ngc-${versions.ngc.version}-rootfs";
              imageRef = versions.triton-trtllm-container.${stdenv.hostPlatform.system}.ref;
              hash = versions.triton-trtllm-container.${stdenv.hostPlatform.system}.hash;
            };
          in
          final.callPackage ../pkgs/ngc-python.nix {
            containerSrc = container;
            inherit (final) nvidia-sdk;
          };

        # libtorch C++ library extracted from NGC python torch
        # Enables hasktorch on aarch64-linux with GPU support
        libtorch-bin = final.callPackage ../pkgs/libtorch.nix { inherit (final) python; };

        cuda-samples = final.callPackage ../pkgs/cuda-samples.nix {
          inherit versions;
          inherit (final) cuda;
        };

        nccl-tests = final.callPackage ../pkgs/nccl-tests.nix {
          inherit (final) cuda;
          inherit (final) nccl;
        };

        validate-sdk = final.callPackage ../pkgs/validate-sdk.nix { inherit (final) nvidia-sdk; };

        monitoring-tools = final.callPackage ../pkgs/monitoring-tools.nix { inherit (final) cuda; };

        nvtop = final.monitoring-tools.nvtop;
        btop-nvml = final.monitoring-tools.btop;

        # Nsight GUI profilers
        nsight-gui-apps = final.callPackage ../pkgs/nsight-gui-apps.nix {
          inherit versions;
          inherit (final) nvidia-sdk;
        };
      };

    nixosModules.default = import ../modules/nvidia-sdk.nix;
    nixosModules.nvidia-sdk = import ../modules/nvidia-sdk.nix;
  };
}
