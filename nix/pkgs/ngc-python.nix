# ngc-python.nix — execute the NGC Python environment without rewriting it.
#
# The container rootfs is the ABI unit.  Keeping its paths intact preserves
# DT_RPATH/DT_RUNPATH, absolute symlinks, ld.so.cache choices, and package
# topology.  The only host ABI boundary is the NVIDIA driver mount.
{
  lib,
  stdenvNoCC,
  bubblewrap,
  writeShellScript,
  containerSrc,
  variant ? "trtllm",
  ...
}:

let
  imagePython = if variant == "trtllm" then "/opt/venv-tritonserver/bin/python3" else "/usr/bin/python3";
  imageSite =
    if variant == "trtllm" then
      "/opt/venv-tritonserver/lib/python3.12/site-packages"
    else
      "/usr/local/lib/python3.12/dist-packages";
  imagePath =
    if variant == "trtllm" then
      "/opt/tritonserver/bin:/opt/venv-tritonserver/bin:/usr/local/nvidia/bin:/usr/local/cuda/bin:/usr/local/mpi/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/local/ucx/bin:/opt/amazon/efa/bin"
    else
      "/opt/tritonserver/bin:/opt/ffmpeg-safe/bin:/usr/local/lib/python3.12/dist-packages/torch_tensorrt/bin:/usr/local/cuda/bin:/usr/local/nixlbench/bin:/usr/local/nixl/bin:/usr/local/nvidia/bin:/usr/local/mpi/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/local/ucx/bin:/opt/amazon/efa/bin:/opt/tensorrt/bin";
  imageLibraryPath =
    (
      if variant == "trtllm" then
        "/usr/local/tensorrt/lib:/usr/local/cuda/compat/lib:/usr/local/nvidia/lib:/usr/local/nvidia/lib64"
      else
        "/opt/ffmpeg-safe/lib:/usr/local/lib/python3.12/dist-packages/torch/lib:/usr/local/lib/python3.12/dist-packages/torch_tensorrt/lib:/usr/local/nixlbench/lib:/usr/local/lib:/opt/amazon/efa/lib:/usr/lib:/usr/local/cuda/compat/lib:/usr/local/nvidia/lib:/usr/local/nvidia/lib64:/usr/local/nixl/lib/x86_64-linux-gnu:/usr/local/nixl/lib/aarch64-linux-gnu"
    )
    + ":/run/opengl-driver/lib";

  launcher = writeShellScript "ngc-${variant}-run" ''
    set -euo pipefail

    args=(
      --die-with-parent
      --new-session
      --ro-bind ${containerSrc} /
      --dev-bind /dev /dev
      --proc /proc
      --ro-bind-try /sys /sys
      --tmpfs /tmp
      --tmpfs /run
      --bind "$PWD" /workspace
      --chdir /workspace
      --setenv HOME /tmp
      --setenv USER triton-server
      --setenv LOGNAME triton-server
      --setenv TMPDIR /tmp
      --setenv TMP /tmp
      --setenv TEMP /tmp
      --setenv PATH ${imagePath}
      --setenv LD_LIBRARY_PATH ${imageLibraryPath}
      --setenv OPAL_PREFIX /opt/hpcx/ompi
      --setenv OMPI_MCA_coll_hcoll_enable 0
      --setenv UCX_MEM_EVENTS no
      --setenv CUDA_HOME /usr/local/cuda
      --setenv TRT_ROOT /usr/local/tensorrt
      --setenv TRITON_PTXAS_PATH /usr/local/cuda/bin/ptxas
      --setenv FLASHINFER_DISABLE_VERSION_CHECK 1
    )

    # NixOS exposes the host driver here.  Mount it at the location NGC's
    # nvidia-container-runtime contract reserves for injected driver DSOs.
    if [[ -d /run/opengl-driver/lib ]]; then
      args+=(--dir /run/opengl-driver --dir /run/opengl-driver/lib)
      for soname in libcuda.so libcuda.so.1 libnvidia-ml.so libnvidia-ml.so.1; do
        if [[ -e "/run/opengl-driver/lib/$soname" ]]; then
          args+=(--ro-bind "$(readlink -f "/run/opengl-driver/lib/$soname")" "/run/opengl-driver/lib/$soname")
        fi
      done
    fi

    # NGC 26.06 contains both scipy/.../_propack.so and the _propack/
    # package.  Python selects the extension first, but it lacks the symbols
    # required by SciPy itself.  Project this one directory faithfully while
    # excluding the vendor-conflicting file; the rootfs remains immutable.
    scipy_linalg=${imageSite}/scipy/sparse/linalg
    if [[ -d ${containerSrc}$scipy_linalg/_propack ]]; then
      args+=(--tmpfs "$scipy_linalg")
      shopt -s nullglob
      for source in ${containerSrc}$scipy_linalg/*; do
        name="''${source##*/}"
        [[ "$name" == _propack.cpython-*.so ]] && continue
        args+=(--ro-bind "$source" "$scipy_linalg/$name")
      done
      shopt -u nullglob
    fi

    exec ${bubblewrap}/bin/bwrap "''${args[@]}" -- "$@"
  '';

  command =
    name: argv:
    stdenvNoCC.mkDerivation {
      pname = "ngc-${variant}-${name}";
      version = containerSrc.name or "ngc";
      dontUnpack = true;
      installPhase = ''
        mkdir -p $out/bin $out/lib/python3.12
        cp ${launcher} $out/libexec-ngc-run
        chmod +x $out/libexec-ngc-run
        printf '%s\n' '#!${stdenvNoCC.shell}' \
          'exec @out@/libexec-ngc-run ${lib.escapeShellArgs argv} "$@"' \
          > $out/bin/${name}
        substituteInPlace $out/bin/${name} --replace-fail @out@ "$out"
        chmod +x $out/bin/${name}
        ln -s ${containerSrc}${imageSite} $out/lib/python3.12/site-packages
      '';
      passthru = {
        inherit containerSrc variant;
        pythonVersion = "3.12";
        sitePackages = "lib/python3.12/site-packages";
      };
      meta = {
        description = "Topology-preserving Python from the NGC ${variant} image";
        homepage = "https://catalog.ngc.nvidia.com";
        license = lib.licenses.unfree;
        platforms = [
          "x86_64-linux"
          "aarch64-linux"
        ];
        mainProgram = name;
      };
    };

  final = command "python3" [ imagePython ];
in
final.overrideAttrs (old: {
  installPhase = old.installPhase + ''
    ln -s python3 $out/bin/python
    ln -s python3 $out/bin/python3.12
    for spec in \
      "pip:${imagePython} -m pip" \
      "torchrun:${imagePython} -m torch.distributed.run"
    do
      name="''${spec%%:*}"
      argv="''${spec#*:}"
      printf '%s\n' '#!${stdenvNoCC.shell}' \
        "exec \"$out/libexec-ngc-run\" $argv \"\$@\"" > "$out/bin/$name"
      chmod +x "$out/bin/$name"
    done
    ${
      if variant == "trtllm" then
        ''
          for cmd in bench build eval prune refit serve; do
            printf '%s\n' '#!${stdenvNoCC.shell}' \
              "exec \"$out/libexec-ngc-run\" ${imagePython} -m \"tensorrt_llm.commands.$cmd\" \"\$@\"" \
              > "$out/bin/trtllm-$cmd"
            chmod +x "$out/bin/trtllm-$cmd"
          done
        ''
      else
        ''
          printf '%s\n' '#!${stdenvNoCC.shell}' \
            "exec \"$out/libexec-ngc-run\" ${imagePython} -m vllm.entrypoints.openai.api_server \"\$@\"" \
            > "$out/bin/vllm"
          chmod +x "$out/bin/vllm"
        ''
    }
  '';
})
