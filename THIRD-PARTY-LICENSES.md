# Third-Party Licenses

This document contains license information for all NVIDIA SDK components included in this project.

## Table of Contents

1. [CUDA Toolkit](#cuda-toolkit)
2. [cuDNN](#cudnn)
3. [TensorRT](#tensorrt)
4. [NCCL](#nccl)
5. [CUTLASS](#cutlass)
6. [cuTensor](#cutensor)
7. [Nsight Tools](#nsight-tools)

______________________________________________________________________

## CUDA Toolkit

**Component:** NVIDIA CUDA Toolkit\
**Version:** See `nix/versions/cuda/default.nix` for current version\
**License Type:** NVIDIA CUDA Toolkit End User License Agreement (EULA)\
**Official License:** https://docs.nvidia.com/cuda/eula/

### Key Redistribution Terms

- CUDA runtime libraries may be redistributed with applications that use them
- Redistribution requires including the NVIDIA copyright notice and license
- The CUDA compiler (nvcc) and development tools are not redistributable
- Sample code may be modified and redistributed
- No reverse engineering, decompilation, or disassembly permitted
- Use is limited to systems with NVIDIA GPUs

______________________________________________________________________

## cuDNN

**Component:** NVIDIA CUDA Deep Neural Network library (cuDNN)\
**Version:** See `nix/versions/cudnn/default.nix` for current version\
**License Type:** NVIDIA cuDNN Software License Agreement (SLA)\
**Official License:** https://docs.nvidia.com/deeplearning/cudnn/sla/index.html

### Key Redistribution Terms

- cuDNN libraries may be redistributed as part of applications
- Must include NVIDIA attribution and license notice
- Cannot be redistributed standalone or as a development kit
- Use restricted to NVIDIA GPU-based systems
- No benchmarking results may be published without NVIDIA approval
- Redistribution of documentation is not permitted

______________________________________________________________________

## TensorRT

**Component:** NVIDIA TensorRT\
**Version:** See `nix/versions/tensorrt/default.nix` for current version\
**License Type:** NVIDIA TensorRT Software License Agreement (SLA) + Apache 2.0 (OSS components)\
**Official License:** https://docs.nvidia.com/deeplearning/tensorrt/sla/index.html

### Key Redistribution Terms

- TensorRT runtime libraries may be redistributed with applications
- Must include NVIDIA copyright notice and license
- Development headers and tools are not redistributable
- Use restricted to NVIDIA GPU-based systems

### Open Source Components

The TensorRT Open Source Software (OSS) repository, including parsers and plugins, is licensed under
Apache License 2.0:

- Repository: https://github.com/NVIDIA/TensorRT
- License: Apache License 2.0
- These components may be freely modified and redistributed under Apache 2.0 terms

______________________________________________________________________

## NCCL

**Component:** NVIDIA Collective Communications Library (NCCL)\
**Version:** See `nix/versions/nccl/default.nix` for current version\
**License Type:** BSD 3-Clause License\
**Source:** https://github.com/NVIDIA/nccl

### Full License Text

```
Copyright (c) 2015-2024, NVIDIA CORPORATION. All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

3. Neither the name of the copyright holder nor the names of its
   contributors may be used to endorse or promote products derived from
   this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

______________________________________________________________________

## CUTLASS

**Component:** CUDA Templates for Linear Algebra Subroutines (CUTLASS)\
**Version:** See `nix/versions/cutlass/default.nix` for current version\
**License Type:** BSD 3-Clause License\
**Source:** https://github.com/NVIDIA/cutlass

### Full License Text

```
Copyright (c) 2017-2024, NVIDIA CORPORATION. All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

3. Neither the name of the copyright holder nor the names of its
   contributors may be used to endorse or promote products derived from
   this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

______________________________________________________________________

## cuTensor

**Component:** NVIDIA cuTENSOR\
**Version:** See `nix/versions/cutensor/default.nix` for current version\
**License Type:** NVIDIA cuTENSOR End User License Agreement (EULA)\
**Official License:** https://docs.nvidia.com/cuda/cutensor/latest/license.html

### Key Redistribution Terms

- cuTENSOR libraries may be redistributed with applications
- Must include NVIDIA copyright notice and license
- Use restricted to NVIDIA GPU-based systems
- No standalone redistribution permitted
- Development headers are not redistributable
- No benchmarking results may be published without NVIDIA approval

______________________________________________________________________

## Nsight Tools

**Component:** NVIDIA Nsight Systems, Nsight Compute, Nsight Graphics\
**Version:** See `nix/versions/nsight/default.nix` for current version\
**License Type:** NVIDIA Software License Agreement\
**Official License:** https://developer.nvidia.com/nvidia-development-tools-solutions-eula

### Key Redistribution Terms

- Nsight tools are NOT redistributable
- Licensed for development and debugging purposes only
- Cannot be included in distributed applications
- Each developer must obtain their own license
- Use requires acceptance of NVIDIA Developer Program terms

______________________________________________________________________

## General Notes

### NVIDIA Software License Compliance

When using NVIDIA SDK components, you must:

1. **Accept License Terms:** All NVIDIA software requires acceptance of applicable license
   agreements
2. **Include Attribution:** Distributed applications must include appropriate copyright notices
3. **GPU Requirement:** Most NVIDIA libraries require NVIDIA GPU hardware for execution
4. **Export Compliance:** NVIDIA software may be subject to U.S. export control laws

### Version Information

All component versions used in this project are defined in the `nix/versions/` directory. Refer to
the specific version files for exact version numbers and SHA256 hashes of distributed binaries.

### Updates

License terms may change between versions. Always refer to the official NVIDIA documentation links
provided above for the most current license terms applicable to the specific version you are using.

______________________________________________________________________

*Last updated: 2024*
