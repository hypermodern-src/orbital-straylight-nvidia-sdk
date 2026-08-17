# wintermute-field

The animated wallpaper of the hypermodern rice, as a CUDA kernel — and a
wayland wallpaper daemon with **no graphics API in it at all**.

The field (orbital horizon, terminator lights, constellation mesh, data
rain, nebula, the maas biochip, the reconcile sweep) exists in one
`__host__ __device__` function in `field.cuh`. The same source lines run
on the CPU and the GPU, which is what makes `--verify` meaningful: render
a frame both ways, compare every channel of every pixel.

```
$ wintermute-field --verify --size 1920x1080
// conformance // cpu vs gpu // max channel diff 0 // mean 0.0000 //
```

Bit-exact. On GB10 (DGX Spark, sm_121):

```
$ wintermute-field --bench --size 3840x2160
// wintermute-field // 3840x2160 // 0.768 ms/frame // 10806.1 Mpix/s // 1303 fps possible //
```

At the daemon's 30fps a 4K wallpaper costs **2.3% of one GPU-second per
second**. The other 97.7% remains available for work.

## the two binaries

- **`wintermute-field`** — CLI. `--out frame.ppm`, `--frames N` for
  sequences, `--theme theme.json` to render any wintermute preset,
  `--bench`, `--verify`, `--cpu`.
- **`wintermute-field-daemon`** — the presenter. A wlr-layer-shell
  background surface whose wl_shm pool is `cudaHostRegister`'d, so the
  kernel writes frames **directly into the compositor's memory**. On GB10
  (coherent unified memory over NVLink-C2C) that is genuinely zero-copy:
  no staging buffer, no `memcpy`, no GL/Vulkan interop — `memfd` →
  `mmap` → `wl_shm` → `cudaHostGetDevicePointer` → kernel writes, the
  compositor composites the same physical pages. On discrete-GPU boxes it
  degrades to one device→host copy per frame, announced on stderr.

The daemon watches wintermute's `theme.json` (~2Hz): palette changes ride
the color spinor (below) over 0.9s, and a generation bump fires the
reconcile sweep — the same choreography as the QML layer it can replace.
Every output gets its own surface, pool and pacing: multi-monitor is
native, hotplug handled in place. Frame-callback paced: fully occluded it
parks in `poll()` at 0% GPU.

## scenes

The kernel carries more than one card. `--scene field` (default) is the
two-axis design space described above; `--scene eyes` is the reference
reel's title-card treatment: plasma blades sweeping the frame (white-hot
head, long cooling tail, every pass re-rolling its lane and speed), the
CASK6 kernel words cycling as big glitch-sliced chromatic-split title
cards, hairline scratches, and a floor that smears everything into
horizontal streaks. The card honors the full two-axis plane — night
emits, day prints ink, affluent tempers the glitch — through one corner
algebra (`CornerInk`). Same conformance story: the scene lives inside the
ONE `__host__ __device__` function, so `--verify --scene eyes` gates it
pixel-for-pixel. Wintermute can flip it live: a `"scene": "eyes"` key in
theme.json overrides the flag on the next ~2Hz tick.

## the color spinor

Chroma lives in the plane perpendicular to the gray axis — the complex
plane of colors, hue as phase, saturation as magnitude. A hue move is a
rotor about that axis (`spinColor`), and palette morphs decompose as
(luma, saturation, hue) with hue riding the rotor the SHORT way around
(`spinorMorph`): red reaches blue through magenta, never through the
desaturated gray an RGB lerp wades through. The daemon uses it for theme
transitions; `--spin θ` on the CLI rotates any palette wholesale.

## the stub-libcuda mirage (NixOS field note)

If this (or any CUDA binary) throws `cudaErrorInsufficientDriver` on a
NixOS box whose driver is plainly new enough: the runtime almost
certainly resolved the **toolkit's stub `libcuda.so`** instead of the
real driver library. The error message lies about the cause; no version
of anything is insufficient. The cure is baked in here via nixpkgs'
`autoAddDriverRunpath` hook (`/run/opengl-driver/lib` in RUNPATH); the
manual equivalent is `LD_LIBRARY_PATH=/run/opengl-driver/lib`.

## building

```
nix build .#… # or:
pkgs.callPackage ./default.nix { cuda = <cudatoolkit>; }
```

Plain-gcc stdenv (nvcc rejects exotic host compilers); wayland targets
build only when the scanner + protocol XMLs are handed to CMake — the
nix expression wires `wlr-protocols` and `wayland-protocols` in.
