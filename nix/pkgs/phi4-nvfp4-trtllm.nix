{
  lib,
  stdenv,
  writeShellScriptBin,
  makeWrapper,
  python312,
  tritonserver,
  cuda,
  git,
  git-lfs,
}:

let
  python = python312;

  # Create a script that downloads and runs Phi-4 FP4 with TensorRT-LLM
  phi4-runner = writeShellScriptBin "phi4-nvfp4-trtllm" ''
        set -e
        
        # Set up environment
        export CUDA_PATH="${cuda}"
        export LD_LIBRARY_PATH="${cuda}/lib64:${tritonserver}/lib:${tritonserver}/tensorrt_llm/lib:''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
        export PATH="${python}/bin:${git}/bin:${git-lfs}/bin:''${PATH:+:$PATH}"
        export PYTHONPATH="${tritonserver}/python:''${PYTHONPATH:+:$PYTHONPATH}"
        
        # Model configuration
        MODEL_NAME="nvidia/Phi-4-multimodal-instruct-NVFP4"
        MODEL_CACHE_DIR="''${XDG_CACHE_HOME:-$HOME/.cache}/huggingface/hub"
        ENGINE_DIR="''${XDG_CACHE_HOME:-$HOME/.cache}/trtllm-engines/phi4-nvfp4"
        
        echo "=== NVIDIA Phi-4 NVFP4 with TensorRT-LLM ==="
        echo ""
        echo "Model: $MODEL_NAME"
        echo "Cache: $MODEL_CACHE_DIR"
        echo "Engine: $ENGINE_DIR"
        echo ""
        
        # Create cache directories
        mkdir -p "$MODEL_CACHE_DIR"
        mkdir -p "$ENGINE_DIR"
        
        # Check if model is already downloaded
        if [ ! -d "$MODEL_CACHE_DIR/models--nvidia--Phi-4-multimodal-instruct-NVFP4" ]; then
          echo "Downloading model from Hugging Face (this may take a while)..."
          echo "Note: You may need to accept the license at:"
          echo "  https://huggingface.co/$MODEL_NAME"
          echo ""
          
      # huggingface-hub should be provided by the python environment.
      # If missing, fail explicitly rather than runtime pip install (supply chain risk).
      if ! ${python}/bin/python -c "import huggingface_hub" 2>/dev/null; then
        echo "ERROR: huggingface-hub not found in python environment." >&2
        echo "Please ensure huggingface-hub is included in the Nix python derivation." >&2
        exit 1
      fi
          
          # Download model
          ${python}/bin/python -c "
    from huggingface_hub import snapshot_download
    import os
    snapshot_download(
        repo_id='$MODEL_NAME',
        cache_dir='$MODEL_CACHE_DIR',
        local_dir_use_symlinks=False,
        token=os.getenv('HF_TOKEN'),
    )
    print('Model downloaded successfully!')
    "
        else
          echo "Model already cached at $MODEL_CACHE_DIR"
        fi
        
        # Run inference with TensorRT-LLM LLM API
        echo ""
        echo "Running inference with TensorRT-LLM..."
        echo "================================================"
        
        ${python}/bin/python << 'PYTHON_EOF'
    import os
    import sys

    # Add TensorRT-LLM to path
    trtllm_path = "${tritonserver}/python"
    if trtllm_path not in sys.path:
        sys.path.insert(0, trtllm_path)

    try:
        from tensorrt_llm import LLM, SamplingParams
    except ImportError as e:
        print(f"Error importing TensorRT-LLM: {e}")
        print(f"Python path: {sys.path}")
        print("Please ensure TensorRT-LLM is properly installed.")
        sys.exit(1)

    def main():
        prompts = [
            "Hello, my name is",
            "The president of the United States is",
            "The capital of France is",
            "The future of AI is",
        ]
        
        sampling_params = SamplingParams(temperature=0.8, top_p=0.95, max_tokens=50)
        
        print("Initializing LLM...")
        print(f"Model: $MODEL_NAME")
        print()
        
        # NOTE: trust_remote_code is intentionally disabled for security.
        # NVIDIA's official Phi-4 NVFP4 model does not require remote code execution.
        # If this fails, verify the model supports standard HF loading.
        llm = LLM(
            model="$MODEL_NAME",
            trust_remote_code=False,
        )
        
        print("Generating responses...")
        print()
        
        outputs = llm.generate(prompts, sampling_params)
        
        # Print the outputs
        for i, output in enumerate(outputs, 1):
            prompt = output.prompt
            generated_text = output.outputs[0].text
            print(f"[{i}] Prompt: {prompt!r}")
            print(f"    Response: {generated_text!r}")
            print()

    if __name__ == '__main__':
        try:
            main()
    except Exception as e:
        # Avoid leaking full paths/stack traces in production
        print(f"Error during inference: {type(e).__name__}: {e}", file=sys.stderr)
        sys.exit(1)
    PYTHON_EOF
  '';

in
stdenv.mkDerivation {
  pname = "phi4-nvfp4-trtllm";
  version = "1.0.0";

  dontUnpack = true;
  dontBuild = true;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    mkdir -p $out/bin
    cp ${phi4-runner}/bin/phi4-nvfp4-trtllm $out/bin/

    # Wrap with proper environment
    wrapProgram $out/bin/phi4-nvfp4-trtllm \
      --prefix PATH : "${
        lib.makeBinPath [
          python
          git
          git-lfs
        ]
      }" \
      --prefix LD_LIBRARY_PATH : "${cuda}/lib64:${tritonserver}/lib" \
      --set CUDA_PATH "${cuda}" \
      --set TRITON_SERVER_ROOT "${tritonserver}"
  '';

  meta = {
    description = "NVIDIA Phi-4 NVFP4 model runner with TensorRT-LLM";
    longDescription = ''
      Runs the NVIDIA Phi-4 multimodal instruct model quantized to FP4 format
      using TensorRT-LLM for high-performance inference on NVIDIA Blackwell GPUs.

      The model is automatically downloaded from Hugging Face on first run.

      Usage:
        nix run .#phi4-nvfp4-trtllm
        
      Requirements:
        - NVIDIA GPU with Blackwell architecture (SM 120) or compatible
        - Hugging Face token (set HF_TOKEN environment variable if model requires auth)
    '';

    homepage = "https://huggingface.co/nvidia/Phi-4-multimodal-instruct-NVFP4";
    license = lib.licenses.unfree;

    platforms = [
      "aarch64-linux"
      "x86_64-linux"
    ];
    mainProgram = "phi4-nvfp4-trtllm";
  };
}
