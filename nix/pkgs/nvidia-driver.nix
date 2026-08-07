# nvidia-driver.nix — the driver, pinned to MATCH the toolkit
#
# One derivation, built from versions.nix via nixpkgs' generic NVIDIA driver
# builder (nvidiaPackages.mkDriver). This is what makes the driver *match*: the
# SDK's driver version is versions.driver.version (610.43.02) — the exact
# driver the CUDA 13.3.1 toolkit was cut against — rather than whatever
# nixpkgs' floating `.latest` resolves to on any given day.
#
# mkDriver is kernel-bound: it compiles nvidia.ko / nvidia-uvm.ko / (open)
# against a specific kernel. Callers pass the kernel-scoped package set as
# `nvidiaPackages` — in the NixOS module that is
# `config.boot.kernelPackages.nvidiaPackages`, so the modules are built for the
# running kernel.
#
# ── The high-integrity hook ──────────────────────────────────────────────
# `openSource` (default null) overrides the open-gpu-kernel-modules source
# mkDriver would otherwise fetch from github.com/NVIDIA. Point it at the
# straylight fork (git.s4.gl/straylight/straylight-nvidia-drivers — 54 coverage
# gates, RapidCheck + libFuzzer, on 610.43.03) to ship the gated modules. Note
# the userspace/kmod version contract: NVIDIA's loader checks that the kernel
# module and userspace .run report the same version string, so a .03 open
# source needs the .03 userspace runfile (a coordinated versions.nix bump), not
# just a source swap. Until then this stays null = stock 610.43.02 open modules.
{
  versions,
  nvidiaPackages,
  # override: a prepared open-gpu-kernel-modules source (fork) + its version
  openSource ? null,
}:
let
  d = versions.driver;

  base = nvidiaPackages.mkDriver {
    inherit (d) version;
    sha256_64bit = d.x86_64-linux.hash;
    sha256_aarch64 = d.aarch64-linux.hash;
    openSha256 = d.openHash;
    settingsSha256 = d.settingsHash;
    persistencedSha256 = d.persistencedHash;
  };

  # Fork swap: replace only the open-kernel-module source, keep everything else.
  driver =
    if openSource == null then
      base
    else
      base.overrideAttrs (old: {
        passthru = (old.passthru or { }) // {
          open = (old.passthru.open or { }).overrideAttrs (_: {
            src = openSource;
          });
        };
      });
in
# Self-consistency: the built driver version MUST equal the pinned spec, so a
# stray nixpkgs-side edit to the generic builder can't silently desync us.
assert driver.version == versions.driver.version;
driver
