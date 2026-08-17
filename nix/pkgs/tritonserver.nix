# tritonserver.nix — run Triton in its pinned NGC rootfs, without ELF mutation.
{
  lib,
  stdenvNoCC,
  bubblewrap,
  containerSrc,
  versions,
  backend ? "trtllm",
  ...
}:

stdenvNoCC.mkDerivation {
  pname = "tritonserver-${backend}";
  version = versions.ngc.version;
  dontUnpack = true;

  installPhase = ''
    mkdir -p $out/bin
    cat > $out/bin/tritonserver <<'EOF'
    #!${stdenvNoCC.shell}
    set -euo pipefail
    args=(
      --die-with-parent --new-session
      --ro-bind ${containerSrc} /
      --dev-bind /dev /dev --proc /proc --ro-bind-try /sys /sys
      --tmpfs /tmp --tmpfs /run
      --bind "$PWD" /workspace --chdir /workspace
      --setenv HOME /tmp
      --setenv USER triton-server --setenv LOGNAME triton-server
      --setenv TMPDIR /tmp --setenv TMP /tmp --setenv TEMP /tmp
      --setenv PATH /opt/tritonserver/bin:/opt/venv-tritonserver/bin:/usr/local/nvidia/bin:/usr/local/cuda/bin:/usr/local/mpi/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/local/ucx/bin:/opt/amazon/efa/bin
      --setenv LD_LIBRARY_PATH /usr/local/tensorrt/lib:/usr/local/cuda/compat/lib:/usr/local/nvidia/lib:/usr/local/nvidia/lib64:/run/opengl-driver/lib
      --setenv OPAL_PREFIX /opt/hpcx/ompi
      --setenv OMPI_MCA_coll_hcoll_enable 0
      --setenv UCX_MEM_EVENTS no
    )
    if [[ -d /run/opengl-driver/lib ]]; then
      args+=(--dir /run/opengl-driver --dir /run/opengl-driver/lib)
      for soname in libcuda.so libcuda.so.1 libnvidia-ml.so libnvidia-ml.so.1; do
        if [[ -e "/run/opengl-driver/lib/$soname" ]]; then
          args+=(--ro-bind "$(readlink -f "/run/opengl-driver/lib/$soname")" "/run/opengl-driver/lib/$soname")
        fi
      done
    fi
    exec ${bubblewrap}/bin/bwrap "''${args[@]}" -- \
      /opt/tritonserver/bin/tritonserver \
      --backend-directory=/opt/tritonserver/backends "$@"
    EOF
    chmod +x $out/bin/tritonserver
  '';

  passthru = { inherit containerSrc backend; };
  meta = {
    description = "Topology-preserving NVIDIA Triton ${backend} runtime";
    homepage = "https://developer.nvidia.com/nvidia-triton-inference-server";
    license = lib.licenses.unfree;
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    mainProgram = "tritonserver";
  };
}
