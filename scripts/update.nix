{
  writeShellApplication,
  curl,
  jq,
  nix,
  awscli2,
  versions,
}:

writeShellApplication {
  name = "nvidia-redist-update";

  runtimeInputs = [
    curl
    jq
    nix
    awscli2
  ];

  text = ''
    set -euo pipefail

    VERSIONS_FILE="nix/versions.nix"
    R2_BUCKET="''${R2_BUCKET:-}"
    R2_ENDPOINT="''${R2_ENDPOINT:-}"
    UPLOAD_TO_R2="''${UPLOAD_TO_R2:-false}"

    echo "nvidia-redist update"
    echo "===================="

    # fetch nvidia redistrib index
    fetch_redist_version() {
      local product="$1"
      local cuda_version="''${2:-13.0}"
      local url="https://developer.download.nvidia.com/compute/$product/redist/redistrib_$cuda_version.json"

      echo "→ fetching $product index..." >&2
      curl -sL "$url" 2>/dev/null || echo "{}"
    }

    # fetch latest cuda version from nvidia
    fetch_cuda_version() {
      echo "→ fetching cuda version..." >&2
      curl -sL "https://developer.download.nvidia.com/compute/cuda/repos/rhel9/x86_64/cuda-toolkit.repo" 2>/dev/null | \
        grep -oP 'cuda-toolkit-\K[0-9]+\.[0-9]+' | head -1 || echo "13.0"
    }

    # nix-prefetch-url for hash
    prefetch_hash() {
      local url="$1"
      echo "→ prefetching $url..." >&2
      nix-prefetch-url --type sha256 "$url" 2>/dev/null | xargs nix hash to-sri --type sha256
    }

    # upload to r2
    upload_to_r2() {
      local file="$1"
      local key="$2"

      if [ "$UPLOAD_TO_R2" = "true" ] && [ -n "$R2_BUCKET" ] && [ -n "$R2_ENDPOINT" ]; then
        echo "→ uploading $key to R2..." >&2
        aws s3 cp "$file" "s3://$R2_BUCKET/$key" \
          --endpoint-url "$R2_ENDPOINT" \
          --quiet
      fi
    }

    # mirror a url to r2 and return new url
    mirror_to_r2() {
      local url="$1"
      local filename
      filename=$(basename "$url")

      if [ "$UPLOAD_TO_R2" = "true" ] && [ -n "$R2_BUCKET" ] && [ -n "$R2_ENDPOINT" ]; then
        local tmpfile
        tmpfile=$(mktemp)
        echo "→ downloading $filename..." >&2
        curl -sL "$url" -o "$tmpfile"
        upload_to_r2 "$tmpfile" "nvidia-redist/$filename"
        rm -f "$tmpfile"
        echo "https://''${R2_BUCKET}.r2.dev/nvidia-redist/$filename"
      else
        echo "$url"
      fi
    }

    # current versions
    echo ""
    echo "current versions:"
    echo "  cuda: ${versions.cuda.version}"
    echo "  cudnn: ${versions.cudnn.version}"
    echo "  nccl: ${versions.nccl.version}"
    echo "  tensorrt: ${versions.tensorrt.version}"
    echo "  cutensor: ${versions.cutensor.version}"
    echo "  cutlass: ${versions.cutlass.version}"
    echo ""

    # check for updates
    echo "checking for updates..."

    CUDNN_INDEX=$(fetch_redist_version "cudnn")
    NCCL_INDEX=$(fetch_redist_version "nccl")
    CUTENSOR_INDEX=$(fetch_redist_version "cutensor")

    CUDNN_LATEST=$(echo "$CUDNN_INDEX" | jq -r '.cudnn.version // empty' 2>/dev/null || echo "")
    NCCL_LATEST=$(echo "$NCCL_INDEX" | jq -r '.nccl.version // empty' 2>/dev/null || echo "")
    CUTENSOR_LATEST=$(echo "$CUTENSOR_INDEX" | jq -r '.libcutensor.version // empty' 2>/dev/null || echo "")

    echo ""
    echo "latest available:"
    [ -n "$CUDNN_LATEST" ] && echo "  cudnn: $CUDNN_LATEST"
    [ -n "$NCCL_LATEST" ] && echo "  nccl: $NCCL_LATEST"
    [ -n "$CUTENSOR_LATEST" ] && echo "  cutensor: $CUTENSOR_LATEST"

    # check cutlass releases
    echo ""
    echo "checking cutlass releases..."
    CUTLASS_LATEST=$(curl -sL "https://api.github.com/repos/NVIDIA/cutlass/releases/latest" | \
      jq -r '.tag_name // "v3.8.0"' | sed 's/^v//')
    echo "  cutlass: $CUTLASS_LATEST"

    echo ""
    echo "to update versions.nix manually:"
    echo "  1. edit nix/versions.nix with new versions"
    echo "  2. run: nix-prefetch-url <url> to get hashes"
    echo "  3. test: nix build .#nvidia-sdk"
    echo ""

    if [ "$UPLOAD_TO_R2" = "true" ]; then
      echo "R2 upload enabled"
      echo "  bucket: $R2_BUCKET"
      echo "  endpoint: $R2_ENDPOINT"
    else
      echo "R2 upload disabled (set UPLOAD_TO_R2=true R2_BUCKET=... R2_ENDPOINT=...)"
    fi
  '';
}
