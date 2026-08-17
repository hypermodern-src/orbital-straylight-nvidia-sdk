// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//                        // wintermute-field // wayland presenter // GB10 //
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//
// The wallpaper daemon with NO graphics API: a wlr-layer-shell background
// surface whose wl_shm buffers are cudaHostRegister'd, so the CUDA kernel
// writes frames DIRECTLY into the compositor's memory — on GB10 (coherent
// unified memory over NVLink-C2C) this is genuinely zero-copy; elsewhere it
// falls back to one device→host memcpy per frame.
//
// EVERY output gets its own surface + pool + frame pacing: multi-monitor is
// native, and output hotplug (add OR remove) is handled in place. Live:
// watches wintermute's theme.json (mtime, ~2Hz) — palette morphs land on
// the next frame, and a GENERATION bump fires the reconcile sweep, same as
// the QML layer. 30fps frame-callback pacing; double-buffered XRGB8888.
//
//   wintermute-field-daemon [--theme PATH] [--fps N] [--scene eyes|field]
//
// SIGTERM-clean.
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

#include "field.cuh"

#include <wayland-client.h>
// The generated C header names a parameter `namespace` — legal C, illegal
// C++/CUDA. The canonical shim renames it in the declarations only.
#define namespace namespace_
#include "wlr-layer-shell-unstable-v1-client-protocol.h"
#undef namespace
#include "xdg-shell-client-protocol.h"

#include <sys/mman.h>
#include <sys/stat.h>
#include <poll.h>
#include <cerrno>
#include <fcntl.h>
#include <unistd.h>
#include <csignal>
#include <ctime>
#include <nvml.h>

// ── BGRA kernel wrapper (wl_shm XRGB8888 is b,g,r,x little-endian) ────────

static __global__ void fieldKernelBGRA(uchar4* out, int w, int h, FieldParams P) {
  int x = blockIdx.x * blockDim.x + threadIdx.x;
  int y = blockIdx.y * blockDim.y + threadIdx.y;
  if (x >= w || y >= h) return;
  float2 uv = f2((x + 0.5f) / w, (y + 0.5f) / h);
  float3 c = fieldColor(uv, P);
  out[y * w + x] = make_uchar4(
      (unsigned char)(clamp01(c.z) * 255.f + 0.5f),   // b
      (unsigned char)(clamp01(c.y) * 255.f + 0.5f),   // g
      (unsigned char)(clamp01(c.x) * 255.f + 0.5f),   // r
      255);
}

// ── state ─────────────────────────────────────────────────────────────────

// One per output: its own layer surface, its own pool, its own pacing. The
// object's address is listener user_data, so Panels live behind pointers and
// are torn down (pending callback included) before deletion.
struct Panel {
  wl_output* output = nullptr;    // nullptr → compositor picks (fallback)
  uint32_t registryName = 0;      // for wl_output removal matching

  wl_surface* surface = nullptr;
  zwlr_layer_surface_v1* layerSurface = nullptr;
  wl_callback* pendingCb = nullptr;

  int width = 0, height = 0;
  bool configured = false;
  bool needsResurface = false;

  // double buffer
  uint8_t* pool = nullptr;
  size_t poolSize = 0;
  wl_buffer* buffers[2] = {};
  uchar4* devPtrs[2] = {};      // device-visible pointers into the pool
  uchar4* devScratch = nullptr; // fallback path when host-register fails
  bool zeroCopy = false;
  int frontBuffer = 0;
  double lastFrame = 0;
};

struct App {
  wl_display* display = nullptr;
  wl_compositor* compositor = nullptr;
  wl_shm* shm = nullptr;
  zwlr_layer_shell_v1* layerShell = nullptr;

  std::vector<Panel*> panels;
  bool running = true;

  // field state (shared across panels — same scene, per-panel aspect)
  FieldParams P{};
  std::string themePath;
  int generation = -1;
  double sweepStart = -1e9;
  // palette morph: theme changes ride the color spinor (hue takes the
  // geodesic around the gray axis) over 0.9s instead of snapping
  float3 palFrom[4]{}, palTo[4]{};
  double palStart = -1e9;
  double lastTick = 0;
  double fpsInterval = 1.0 / 30.0;
  long framesLeft = -1;         // --frames N: exit after N renders (test mode)

  // live GPU telemetry (NVML) — the field breathes with the real machine
  bool nvmlOk = false;
  nvmlDevice_t nvmlDev{};
  float loadTarget = 0.f;
  float powerTarget = 0.f;
};

static App app;

static double nowSec() {
  timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return ts.tv_sec + ts.tv_nsec * 1e-9;
}

// ── theme watch (palette + generation → sweep) ────────────────────────────

static int readGeneration(const std::string& path) {
  std::ifstream f(path);
  if (!f) return -1;
  char buf[8192];                 // "generation" sits at the head of theme.json
  f.read(buf, sizeof(buf));
  std::string s(buf, (size_t)f.gcount());
  auto r = s.find("\"generation\"");
  if (r == std::string::npos) return -1;
  auto colon = s.find(':', r);
  return colon == std::string::npos ? -1 : atoi(s.c_str() + colon + 1);
}

static void themeTick() {
  if (app.themePath.empty()) return;
  // Parse into the current TARGETS, not the live palette: scene/register
  // apply immediately, but a palette change only retargets the morph — the
  // live colors ride the spinor from wherever they are now (mid-morph safe).
  FieldParams tmp = app.P;
  tmp.surface = app.palTo[0]; tmp.paper   = app.palTo[1];
  tmp.accent  = app.palTo[2]; tmp.accentD = app.palTo[3];
  loadTheme(app.themePath, tmp);
  app.P.reg = tmp.reg;
  app.P.scene = tmp.scene;
  float3 nt[4] = {tmp.surface, tmp.paper, tmp.accent, tmp.accentD};
  bool changed = false;
  for (int i = 0; i < 4; i++)
    changed = changed || nt[i].x != app.palTo[i].x || nt[i].y != app.palTo[i].y ||
              nt[i].z != app.palTo[i].z;
  if (changed) {
    app.palFrom[0] = app.P.surface; app.palFrom[1] = app.P.paper;
    app.palFrom[2] = app.P.accent;  app.palFrom[3] = app.P.accentD;
    for (int i = 0; i < 4; i++) app.palTo[i] = nt[i];
    // first load (before generation is known) snaps; every later one morphs
    app.palStart = app.generation >= 0 ? nowSec() : -1e9;
  }
  int g = readGeneration(app.themePath);
  if (g >= 0 && g != app.generation) {
    if (app.generation >= 0) app.sweepStart = nowSec();   // not on first load
    app.generation = g;
  }
}

// Poll GPU utilization + power draw. Best-effort: if NVML is unavailable the
// targets stay 0 and the field renders its calm idle state.
static void nvmlPoll() {
  if (!app.nvmlOk) return;
  nvmlUtilization_t u;
  if (nvmlDeviceGetUtilizationRates(app.nvmlDev, &u) == NVML_SUCCESS)
    app.loadTarget = u.gpu * 0.01f;
  unsigned int mw = 0;
  if (nvmlDeviceGetPowerUsage(app.nvmlDev, &mw) == NVML_SUCCESS)
    app.powerTarget = fminf(1.f, (mw * 1e-3f) / 140.f);   // ~140W board ceiling
}

// ── per-panel surface lifecycle ───────────────────────────────────────────

static void teardownPanel(Panel* p) {
  if (p->pendingCb) { wl_callback_destroy(p->pendingCb); p->pendingCb = nullptr; }
  if (p->zeroCopy) { cudaHostUnregister(p->pool); p->zeroCopy = false; }
  if (p->devScratch) { cudaFree(p->devScratch); p->devScratch = nullptr; }
  if (p->pool && p->pool != MAP_FAILED) { munmap(p->pool, p->poolSize); }
  p->pool = nullptr; p->poolSize = 0;
  for (int i = 0; i < 2; i++) { if (p->buffers[i]) wl_buffer_destroy(p->buffers[i]); p->buffers[i] = nullptr; }
  p->devPtrs[0] = p->devPtrs[1] = nullptr;
  if (p->layerSurface) { zwlr_layer_surface_v1_destroy(p->layerSurface); p->layerSurface = nullptr; }
  if (p->surface) { wl_surface_destroy(p->surface); p->surface = nullptr; }
  p->configured = false;
}

static void layerConfigure(void* data, zwlr_layer_surface_v1* ls, uint32_t serial,
                           uint32_t w, uint32_t h) {
  Panel* p = (Panel*)data;
  zwlr_layer_surface_v1_ack_configure(ls, serial);
  if (w && h) { p->width = (int)w; p->height = (int)h; }
  p->configured = true;
}

// The compositor destroyed a layer surface — happens on output
// reconfiguration (resolution/scale change, monitor hotplug, DPMS, login).
// Do NOT exit: rebuild that panel in place. Exiting here is what blanked the
// desktop (with a restart) or flickered it (with Restart=always).
static void layerClosed(void* data, zwlr_layer_surface_v1*) {
  ((Panel*)data)->needsResurface = true;
}
static const zwlr_layer_surface_v1_listener layerListener = {layerConfigure, layerClosed};

static bool makeBuffers(Panel* p) {
  size_t stride = size_t(p->width) * 4;
  size_t frame = stride * p->height;
  p->poolSize = frame * 2;

  int fd = memfd_create("wintermute-field", MFD_CLOEXEC);
  if (fd < 0 || ftruncate(fd, p->poolSize) < 0) return false;
  p->pool = (uint8_t*)mmap(nullptr, p->poolSize, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
  if (p->pool == MAP_FAILED) return false;

  wl_shm_pool* pool = wl_shm_create_pool(app.shm, fd, (int)p->poolSize);
  for (int i = 0; i < 2; i++)
    p->buffers[i] = wl_shm_pool_create_buffer(pool, (int)(i * frame), p->width,
                                              p->height, (int)stride, WL_SHM_FORMAT_XRGB8888);
  wl_shm_pool_destroy(pool);
  close(fd);

  // the GB10 move: register the compositor's own memory with CUDA
  if (cudaHostRegister(p->pool, p->poolSize,
                       cudaHostRegisterMapped | cudaHostRegisterPortable) == cudaSuccess) {
    void* dp = nullptr;
    if (cudaHostGetDevicePointer(&dp, p->pool, 0) == cudaSuccess) {
      p->devPtrs[0] = (uchar4*)dp;
      p->devPtrs[1] = (uchar4*)((uint8_t*)dp + frame);
      p->zeroCopy = true;
    }
  }
  if (!p->zeroCopy) {
    if (cudaMalloc(&p->devScratch, frame) != cudaSuccess) return false;
    fprintf(stderr, "wintermute-field-daemon: host-register unavailable; memcpy path\n");
  } else {
    fprintf(stderr, "wintermute-field-daemon: ZERO-COPY — kernel writes the compositor's pool\n");
  }
  return true;
}

static bool pumpEvents(int timeoutMs);

static bool setupPanel(Panel* p) {
  p->configured = false;
  p->surface = wl_compositor_create_surface(app.compositor);
  // BOTTOM, not BACKGROUND: the wlr layer order is background < bottom < top,
  // so this deterministically stacks ABOVE the QML wallpaper (which holds
  // BACKGROUND as the always-present safety-net floor) and below windows. No
  // creation-order race between the two renderers — the field wins when it's
  // up, the QML floor shows through the instant it isn't. Never a blank desktop.
  p->layerSurface = zwlr_layer_shell_v1_get_layer_surface(
      app.layerShell, p->surface, p->output,
      ZWLR_LAYER_SHELL_V1_LAYER_BOTTOM, "wintermute-field");
  zwlr_layer_surface_v1_add_listener(p->layerSurface, &layerListener, p);
  zwlr_layer_surface_v1_set_anchor(p->layerSurface,
      ZWLR_LAYER_SURFACE_V1_ANCHOR_TOP | ZWLR_LAYER_SURFACE_V1_ANCHOR_BOTTOM |
      ZWLR_LAYER_SURFACE_V1_ANCHOR_LEFT | ZWLR_LAYER_SURFACE_V1_ANCHOR_RIGHT);
  zwlr_layer_surface_v1_set_exclusive_zone(p->layerSurface, -1);
  wl_surface_commit(p->surface);

  for (int i = 0; !p->configured && i < 30; i++)
    if (!pumpEvents(100)) return false;         // display died → let main exit→restart
  if (!p->configured) return false;
  if (p->width <= 0 || p->height <= 0) { p->width = 1920; p->height = 1080; }
  return makeBuffers(p);
}

// ── render + frame pacing (per panel) ─────────────────────────────────────

static void frameDone(void* data, wl_callback* cb, uint32_t);
static const wl_callback_listener frameListener = {frameDone};

static void scheduleFrame(Panel* p) {
  p->pendingCb = wl_surface_frame(p->surface);
  wl_callback_add_listener(p->pendingCb, &frameListener, p);
  wl_surface_commit(p->surface);
}

static void renderFrame(Panel* p) {
  if (!p->configured || p->needsResurface || !p->surface) return;
  double t = nowSec();
  app.P.aspect = (float)p->width / p->height;
  app.P.time = (float)fmod(t, 86400.0);

  // ease live telemetry into the field (the 2Hz poll reads as a smooth breath)
  app.P.load += (app.loadTarget - app.P.load) * 0.06f;
  app.P.power += (app.powerTarget - app.P.power) * 0.06f;

  // the palette rides the spinor: recomputed from endpoints every frame
  // (stateless), landing exactly on the target at u=1
  float mu = (float)((t - app.palStart) / 0.9);
  mu = mu < 0.f ? 0.f : (mu > 1.f ? 1.f : mu);
  mu = mu * mu * (3.f - 2.f * mu);
  app.P.surface = spinorMorph(app.palFrom[0], app.palTo[0], mu);
  app.P.paper   = spinorMorph(app.palFrom[1], app.palTo[1], mu);
  app.P.accent  = spinorMorph(app.palFrom[2], app.palTo[2], mu);
  app.P.accentD = spinorMorph(app.palFrom[3], app.palTo[3], mu);

  // reconcile sweep: 0.9s pass on generation change, parked otherwise
  double sw = t - app.sweepStart;
  app.P.sweep = (sw >= 0 && sw < 0.9) ? (float)(-0.15 + 1.30 * (sw / 0.9)) : -1.f;

  int b = p->frontBuffer ^ 1;
  size_t frame = size_t(p->width) * p->height;
  dim3 block(16, 16), grid((p->width + 15) / 16, (p->height + 15) / 16);

  if (p->zeroCopy) {
    fieldKernelBGRA<<<grid, block>>>(p->devPtrs[b], p->width, p->height, app.P);
    cudaDeviceSynchronize();
  } else {
    fieldKernelBGRA<<<grid, block>>>(p->devScratch, p->width, p->height, app.P);
    cudaMemcpy(p->pool + b * frame * 4, p->devScratch, frame * 4, cudaMemcpyDeviceToHost);
  }

  wl_surface_attach(p->surface, p->buffers[b], 0, 0);
  wl_surface_damage_buffer(p->surface, 0, 0, p->width, p->height);
  p->frontBuffer = b;
  p->lastFrame = t;
  if (app.framesLeft > 0 && --app.framesLeft == 0) app.running = false;
}

static void frameDone(void* data, wl_callback* cb, uint32_t) {
  Panel* p = (Panel*)data;
  wl_callback_destroy(cb);
  p->pendingCb = nullptr;
  if (p->needsResurface || !p->surface) return;   // rebuild path owns the loop
  double t = nowSec();

  if (t - app.lastTick >= 0.5) { app.lastTick = t; themeTick(); nvmlPoll(); }

  if (t - p->lastFrame >= app.fpsInterval)
    renderFrame(p);
  scheduleFrame(p);
}

// ── wayland plumbing ──────────────────────────────────────────────────────

static bool registryReady() {
  return app.compositor && app.shm && app.layerShell;
}

static void registryGlobal(void*, wl_registry* reg, uint32_t name,
                           const char* iface, uint32_t) {
  if (!strcmp(iface, wl_compositor_interface.name))
    app.compositor = (wl_compositor*)wl_registry_bind(reg, name, &wl_compositor_interface, 4);
  else if (!strcmp(iface, wl_shm_interface.name))
    app.shm = (wl_shm*)wl_registry_bind(reg, name, &wl_shm_interface, 1);
  else if (!strcmp(iface, zwlr_layer_shell_v1_interface.name))
    app.layerShell = (zwlr_layer_shell_v1*)wl_registry_bind(reg, name, &zwlr_layer_shell_v1_interface, 1);
  else if (!strcmp(iface, wl_output_interface.name)) {
    Panel* p = new Panel();
    p->output = (wl_output*)wl_registry_bind(reg, name, &wl_output_interface, 1);
    p->registryName = name;
    app.panels.push_back(p);
    // hotplug after startup: bring the new panel up from the run loop
    if (registryReady()) p->needsResurface = true;
  }
}

static void registryGlobalRemove(void*, wl_registry*, uint32_t name) {
  for (size_t i = 0; i < app.panels.size(); i++) {
    Panel* p = app.panels[i];
    if (p->output && p->registryName == name) {
      teardownPanel(p);
      wl_output_destroy(p->output);   // bound at v1: release() doesn't exist yet
      app.panels.erase(app.panels.begin() + i);
      delete p;
      fprintf(stderr, "wintermute-field-daemon: output removed; %zu panel(s) remain\n",
              app.panels.size());
      return;
    }
  }
}
static const wl_registry_listener registryListener = {registryGlobal, registryGlobalRemove};

static int sigPipe[2] = {-1, -1};
static void onSignal(int) {
  app.running = false;
  char b = 1;
  (void)!write(sigPipe[1], &b, 1);
}

// the thread-safe wayland read pattern: dispatch what's queued, flush,
// then poll on {display, signal pipe} — timeoutMs < 0 blocks forever.
// Returns false when the loop should stop (signal, error, timeout).
static bool pumpEvents(int timeoutMs) {
  while (wl_display_prepare_read(app.display) != 0)
    if (wl_display_dispatch_pending(app.display) < 0) return false;
  wl_display_flush(app.display);
  pollfd fds[2] = {{wl_display_get_fd(app.display), POLLIN, 0},
                   {sigPipe[0], POLLIN, 0}};
  int r;
  do { r = poll(fds, 2, timeoutMs); } while (r < 0 && errno == EINTR);
  if (fds[0].revents & POLLIN) {
    if (wl_display_read_events(app.display) < 0) return false;
  } else {
    wl_display_cancel_read(app.display);
  }
  if (r <= 0) return false;                       // error or timeout
  if (fds[1].revents & POLLIN) return false;      // signal
  return wl_display_dispatch_pending(app.display) >= 0;
}

// ── main ──────────────────────────────────────────────────────────────────

int main(int argc, char** argv) {
  const char* home = getenv("HOME");
  const char* xdgState = getenv("XDG_STATE_HOME");
  app.themePath = xdgState ? std::string(xdgState) + "/wintermute/theme.json"
                           : std::string(home ? home : "") + "/.local/state/wintermute/theme.json";

  // defaults match the QML layer
  app.P.time = 8.f; app.P.reg = 1.f; app.P.grain = 0.02f; app.P.sweep = -1.f;
  app.P.surface = f3(0.098f, 0.110f, 0.122f);
  app.P.paper   = f3(0.118f, 0.137f, 0.161f);
  app.P.accent  = f3(0.322f, 0.647f, 1.f);
  app.P.accentD = f3(0.502f, 0.824f, 1.f);
  // morph endpoints start AT the defaults — a missing theme.json must render
  // the default palette, not a morph toward zero-initialized black
  app.palFrom[0] = app.palTo[0] = app.P.surface;
  app.palFrom[1] = app.palTo[1] = app.P.paper;
  app.palFrom[2] = app.palTo[2] = app.P.accent;
  app.palFrom[3] = app.palTo[3] = app.P.accentD;

  for (int i = 1; i < argc; i++) {
    std::string a = argv[i];
    auto next = [&]() -> const char* { return i + 1 < argc ? argv[++i] : ""; };
    if (a == "--theme") app.themePath = next();
    else if (a == "--scene") app.P.scene = std::string(next()) == "eyes" ? 1 : 0;
    else if (a == "--fps") app.fpsInterval = 1.0 / atof(next());
    else if (a == "--frames") app.framesLeft = atol(next());
  }
  themeTick();
  app.generation = readGeneration(app.themePath);   // no sweep on boot

  if (nvmlInit() == NVML_SUCCESS &&
      nvmlDeviceGetHandleByIndex(0, &app.nvmlDev) == NVML_SUCCESS) {
    app.nvmlOk = true;
    nvmlPoll();
    fprintf(stderr, "wintermute-field-daemon: NVML live — curtains track the GPU\n");
  } else {
    fprintf(stderr, "wintermute-field-daemon: NVML unavailable — field runs idle\n");
  }

  if (pipe(sigPipe) < 0) { perror("pipe"); return 1; }
  signal(SIGINT, onSignal);
  signal(SIGTERM, onSignal);
  // A wallpaper daemon must not fall over to a stray signal. SIGTERM/SIGINT
  // are the only ways out (systemd stop). Everything else is ignored: SIGHUP
  // (session/terminal hangup), SIGUSR1/2 (someone's kill -USR1), SIGPIPE (a
  // broken write surfaces as EPIPE, never a death).
  signal(SIGHUP, SIG_IGN);
  signal(SIGPIPE, SIG_IGN);
  signal(SIGUSR1, SIG_IGN);
  signal(SIGUSR2, SIG_IGN);

  app.display = wl_display_connect(nullptr);
  if (!app.display) { fprintf(stderr, "no wayland display\n"); return 1; }

  wl_registry* reg = wl_display_get_registry(app.display);
  wl_registry_add_listener(reg, &registryListener, nullptr);
  wl_display_roundtrip(app.display);
  if (!registryReady()) {
    fprintf(stderr, "missing globals (compositor/shm/layer-shell)\n");
    return 1;
  }
  // no outputs advertised (headless-ish): one compositor-chosen panel
  if (app.panels.empty()) app.panels.push_back(new Panel());

  int up = 0;
  for (Panel* p : app.panels)
    if (setupPanel(p)) {
      fprintf(stderr, "wintermute-field-daemon: panel %dx%d\n", p->width, p->height);
      renderFrame(p);
      scheduleFrame(p);
      up++;
    } else {
      p->needsResurface = true;   // retry from the run loop
    }
  if (!up) { fprintf(stderr, "no configure from compositor\n"); return 1; }
  fprintf(stderr, "wintermute-field-daemon: %d/%zu panel(s) up, theme %s\n",
          up, app.panels.size(), app.themePath.c_str());

  // The run loop. Frame callbacks pace us when visible; fully occluded we park
  // in poll at 0% GPU. When the compositor tears a surface down we rebuild
  // that panel in place (new size and all) rather than exiting — seamless
  // across output reconfiguration, and immune to a reconfiguration STORM.
  while (app.running) {
    Panel* broken = nullptr;
    for (Panel* p : app.panels)
      if (p->needsResurface) { broken = p; break; }
    if (broken) {
      broken->needsResurface = false;
      teardownPanel(broken);
      timespec settle{0, 150 * 1000 * 1000};   // 150ms: let the reconfig settle
      nanosleep(&settle, nullptr);
      if (!setupPanel(broken)) {
        teardownPanel(broken);
        // Tell apart a DEAD display (compositor gone → exit, let systemd
        // restart us fresh) from a live display whose output isn't usable yet
        // (a monitor unplugged/disabled). In the latter we must NOT exit and
        // churn through restarts — keep the process alive and retry until the
        // output returns. A signal still breaks us out via pumpEvents.
        if (wl_display_get_error(app.display) != 0) {
          fprintf(stderr, "wintermute-field-daemon: display gone; exit for restart\n");
          break;
        }
        broken->needsResurface = true;           // retry this panel next pass
        timespec backoff{0, 500 * 1000 * 1000};
        nanosleep(&backoff, nullptr);
        continue;
      }
      fprintf(stderr, "wintermute-field-daemon: panel rebuilt %dx%d\n",
              broken->width, broken->height);
      renderFrame(broken);
      scheduleFrame(broken);
      continue;
    }
    if (!pumpEvents(-1)) break;
  }

  for (Panel* p : app.panels) { teardownPanel(p); delete p; }
  app.panels.clear();
  if (app.nvmlOk) nvmlShutdown();
  wl_display_disconnect(app.display);
  return 0;
}
