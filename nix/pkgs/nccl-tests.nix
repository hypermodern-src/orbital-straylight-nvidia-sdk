{
  lib,
  stdenv,
  fetchFromGitHub,
  cuda,
  nccl,
  openmpi,
  withMPI ? true,
  cudaArch ? if stdenv.hostPlatform.isAarch64 then "sm_100" else "sm_120",
}:

let
  version = "2.13.10";
in
stdenv.mkDerivation {
  pname = "nccl-tests";
  inherit version;

  src = fetchFromGitHub {
    owner = "NVIDIA";
    repo = "nccl-tests";
    rev = "v${version}";
    hash = "sha256-H9shp4fYW+dlyL9FZRxX761UCFR/pOBKNHfVme2TfJg=";
  };

  buildInputs = [
    cuda
    nccl
  ]
  ++ lib.optionals withMPI [ openmpi ];

  enableParallelBuilding = true;

  preBuild =
    let
      smNum = lib.removePrefix "sm_" cudaArch;
    in
    ''
      export NVCC_GENCODE="-gencode=arch=compute_${smNum},code=${cudaArch}"
      export NIX_LDFLAGS="$NIX_LDFLAGS -L${nccl}/lib"
    '';

  makeFlags = [
    "CUDA_HOME=${cuda}"
    "NCCL_HOME=${nccl}"
  ]
  ++ lib.optionals withMPI [
    "MPI=1"
    "MPI_HOME=${openmpi}"
  ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    cp -v build/*_perf $out/bin/

    mkdir -p $out/share/doc/nccl-tests
    cp -v README.md doc/*.md $out/share/doc/nccl-tests/ 2>/dev/null || true

    runHook postInstall
  '';

  meta = {
    description = "NCCL Tests - Performance and correctness tests for NVIDIA NCCL";
    homepage = "https://github.com/NVIDIA/nccl-tests";
    license = lib.licenses.bsd3;
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    maintainers = [ ];
  };
}
