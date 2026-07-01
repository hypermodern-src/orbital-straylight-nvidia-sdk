# nix/versions/nsight/default.nix — Nsight Profiling Tools Versions
#
# NVIDIA Nsight Compute and Systems profiling tool versions.

_:

{
  nsight = {
    compute = {
      version = "2025.4.0";
      x86_64-linux.path = "host/linux-desktop-glibc_2_11_3-x64";
      aarch64-linux.path = "host/linux-desktop-t210-a64";
    };

    systems = {
      version = "2025.5.2";
      x86_64-linux.path = "host-linux-x64";
      aarch64-linux.path = "host-linux-armv8";
    };
  };
}
