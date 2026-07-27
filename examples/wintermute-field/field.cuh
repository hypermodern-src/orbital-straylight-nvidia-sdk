#pragma once
/*
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                                  wintermute // nv // field
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//
The animated wallpaper field (nixos-config wallpaper.frag) expressed as a
CUDA kernel — the register-morphing two-axis design space, faithful port:
nebula, bloom orbits, orbital horizon with terminator lights, constellation
+ telemetry mesh, scanlines, data rain, the maas biochip, the reconcile
sweep, grain and dither.
//
The field is ONE __host__ __device__ function, so CPU/GPU conformance is
built in (`--verify` renders a frame both ways and reports max channel
diff — the parity-gate doctrine, applied to pixels).
//
Modern nv: C++20, thrust device vectors for the framebuffer, cuda::std
where it earns its keep. Palette arrives from wintermute's theme.json
(`--theme`) or flags.
//
  wintermute-field --size 3840x2160 --time 12.5 --reg 1.0 \
      --theme ~/.local/state/wintermute/theme.json --out /tmp/field.ppm
  wintermute-field --bench          # Mpix/s on the resident GB10
  wintermute-field --verify         # CPU vs GPU conformance
//
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
*/

#include <cstdio>
#include <cstdint>
#include <cstring>
#include <cmath>
#include <string>
#include <fstream>
#include <sstream>
#include <chrono>
#include <vector>

#include <cuda_runtime.h>
#include <thrust/device_vector.h>
#include <thrust/host_vector.h>

// ── float3 helpers (host+device) ──────────────────────────────────────────

#define HD __host__ __device__ __forceinline__

HD float3 f3(float x, float y, float z) { return make_float3(x, y, z); }
HD float3 operator+(float3 a, float3 b) { return f3(a.x + b.x, a.y + b.y, a.z + b.z); }
HD float3 operator-(float3 a, float3 b) { return f3(a.x - b.x, a.y - b.y, a.z - b.z); }
HD float3 operator*(float3 a, float s) { return f3(a.x * s, a.y * s, a.z * s); }
HD float3 operator*(float s, float3 a) { return a * s; }
HD float3 operator*(float3 a, float3 b) { return f3(a.x * b.x, a.y * b.y, a.z * b.z); }
HD float2 f2(float x, float y) { return make_float2(x, y); }
HD float2 operator+(float2 a, float2 b) { return f2(a.x + b.x, a.y + b.y); }
HD float2 operator-(float2 a, float2 b) { return f2(a.x - b.x, a.y - b.y); }
HD float2 operator*(float2 a, float s) { return f2(a.x * s, a.y * s); }

HD float fractf(float x) { return x - floorf(x); }
HD float mixf(float a, float b, float t) { return a + (b - a) * t; }
HD float3 mix3(float3 a, float3 b, float t) { return a + (b - a) * t; }
HD float clamp01(float x) { return fminf(1.f, fmaxf(0.f, x)); }
HD float smoothstepf(float e0, float e1, float x) {
  float t = clamp01((x - e0) / (e1 - e0));
  return t * t * (3.f - 2.f * t);
}
HD float stepf(float e, float x) { return x >= e ? 1.f : 0.f; }
HD float dot2(float2 a, float2 b) { return a.x * b.x + a.y * b.y; }
HD float len2(float2 a) { return sqrtf(dot2(a, a)); }

// ── the shader's primitives, verbatim ─────────────────────────────────────

HD float hashf(float2 p) {
  p = f2(fractf(p.x * 123.34f), fractf(p.y * 456.21f));
  float d = p.x * (p.x + 45.32f) + p.y * (p.y + 45.32f);
  p = f2(p.x + d, p.y + d);
  return fractf(p.x * p.y);
}

HD float vnoise(float2 p) {
  float2 i = f2(floorf(p.x), floorf(p.y));
  float2 fr = f2(fractf(p.x), fractf(p.y));
  float2 u = f2(fr.x * fr.x * (3.f - 2.f * fr.x), fr.y * fr.y * (3.f - 2.f * fr.y));
  float a = hashf(i);
  float b = hashf(i + f2(1, 0));
  float c = hashf(i + f2(0, 1));
  float d = hashf(i + f2(1, 1));
  return mixf(mixf(a, b, u.x), mixf(c, d, u.x), u.y);
}

HD float fbm2(float2 p) {
  return 0.65f * vnoise(p) + 0.35f * vnoise(f2(p.x * 2.13f + 17.7f, p.y * 2.13f + 17.7f));
}

struct Star { float2 pos; float on; };

HD Star starIn(float2 cell, float gate) {
  float h = hashf(cell);
  float2 jitter = f2((hashf(cell + f2(1.7f, 1.7f)) - 0.5f) * 0.7f,
                     (hashf(cell + f2(3.1f, 3.1f)) - 0.5f) * 0.7f);
  return {jitter, stepf(gate, h)};
}

HD float segDist(float2 p, float2 a, float2 b) {
  float2 ab = b - a;
  float t = clamp01(dot2(p - a, ab) / fmaxf(dot2(ab, ab), 1e-5f));
  return len2(p - a - ab * t);
}

// ── uniforms ──────────────────────────────────────────────────────────────

struct FieldParams {
  float time;
  float reg;      // register, 0 affluent … 1 facility
  float grain;
  float aspect;
  float sweep;    // -1 parked; 0..1 during a reconcile pass
  float load;     // live GPU utilization 0..1 — drives the beam curtains
  float power;    // live GPU power draw, normalized — heats the curtain tips
  float3 surface, paper, accent, accentD;
};

// 5x7 uppercase font (row-major, low 5 bits) — the CASK6 lingo.
// index via glyphIndex(); each glyph is 7 rows.
HD int glyphIndex(char c) {
  const char* o = " .:_0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ";
  for (int i = 0; o[i]; i++) if (o[i] == c) return i;
  return 0;
}
HD unsigned int glyphRow(int gi, int row) {
  static const unsigned char F[40][7] = {
    {0,0,0,0,0,0,0},
    {0,0,0,0,0,6,6},
    {0,6,6,0,6,6,0},
    {0,0,0,0,0,0,31},
    {14,17,19,21,25,17,14},
    {4,12,4,4,4,4,14},
    {14,17,1,2,4,8,31},
    {31,2,4,2,1,17,14},
    {2,6,10,18,31,2,2},
    {31,16,30,1,1,17,14},
    {6,8,16,30,17,17,14},
    {31,1,2,4,8,8,8},
    {14,17,17,14,17,17,14},
    {14,17,17,15,1,2,12},
    {14,17,17,31,17,17,17},
    {30,17,17,30,17,17,30},
    {14,17,16,16,16,17,14},
    {28,18,17,17,17,18,28},
    {31,16,16,30,16,16,31},
    {31,16,16,30,16,16,16},
    {14,17,16,23,17,17,15},
    {17,17,17,31,17,17,17},
    {14,4,4,4,4,4,14},
    {7,2,2,2,2,18,12},
    {17,18,20,24,20,18,17},
    {16,16,16,16,16,16,31},
    {17,27,21,21,17,17,17},
    {17,17,25,21,19,17,17},
    {14,17,17,17,17,17,14},
    {30,17,17,30,16,16,16},
    {14,17,17,17,21,18,13},
    {30,17,17,30,20,18,17},
    {15,16,16,14,1,1,30},
    {31,4,4,4,4,4,4},
    {17,17,17,17,17,17,14},
    {17,17,17,17,17,10,4},
    {17,17,17,21,21,27,17},
    {17,17,10,4,10,17,17},
    {17,17,10,4,4,4,4},
    {31,1,2,4,8,16,31},
  };
  if (gi < 0 || gi >= 40 || row < 0 || row > 6) return 0u;
  return F[gi][row];
}
// ── the kernel word: render a 5x7 bitmap string as glowing digital text ────
// Hard pixels (the data aesthetic) + a soft bounding-box halo (words emit
// light, cf. ESCAPE / EYES / REAL in the reference reel).
HD float renderWord(float2 uv, const char* word, int wlen,
                    float ox, float oy, float gh, float aspect) {
  float ty01 = (uv.y - oy) / gh;
  if (ty01 < 0.f || ty01 > 1.f) return 0.f;
  float gwuv = gh * (5.f / 7.f) / aspect;   // glyph width in uv.x, square pixels
  float adv = gwuv * 1.18f;                 // advance incl. gap
  float rel = uv.x - ox;
  if (rel < 0.f) return 0.f;
  int ci = (int)(rel / adv);
  if (ci < 0 || ci >= wlen) return 0.f;
  float lx01 = (rel - ci * adv) / gwuv;     // 0..1 across the glyph
  if (lx01 > 1.f) return 0.f;               // in the inter-glyph gap
  int gx = (int)(lx01 * 5.f);
  int gy = (int)(ty01 * 7.f);
  if (gx < 0 || gx > 4 || gy < 0 || gy > 6) return 0.f;
  unsigned int bits = glyphRow(glyphIndex(word[ci]), gy);
  return ((bits >> (4 - gx)) & 1u) ? 1.f : 0.f;
}

// One big CASK6 word at a time, cycling, glitch-revealed. Returns glow.
HD float kernelGlyphs(float2 uv, float t, float aspect, float load, float3& tint,
                      float3 accent, float3 accentD) {
  const char* W[8] = { "TCGEN05.MMA", "WGMMA.SYNC", "CP.ASYNC.BULK",
                       "MBARRIER.ARRIVE", "SM_121A", "CASK6::GRAPH",
                       "TMEM_LD", "XMMA_GEMM_F16" };
  const int  L[8] = { 11, 10, 13, 15, 7, 12, 7, 13 };
  float period = 3.6f;
  int wi = ((int)(t / period)) & 7;
  float ph = fractf(t / period);
  const char* w = W[wi];
  int wl = L[wi];
  // life: glitch-in, hold, cut out
  float vis = smoothstepf(0.f, 0.10f, ph) * smoothstepf(1.f, 0.82f, ph);

  float gh = 0.16f + 0.05f * hashf(f2((float)wi, 2.2f));
  float gwuv = gh * (5.f / 7.f) / aspect;
  float wordW = wl * gwuv * 1.18f;
  float ox = 0.5f - wordW * 0.5f;
  float oy = 0.08f + 0.15f * hashf(f2((float)wi, 5.5f));

  // horizontal RGB-split glitch: per-scanline jitter, strong during reveal
  float rev = 1.f - smoothstepf(0.f, 0.30f, ph);
  float band = floorf(uv.y * 46.f);
  float gj = (hashf(f2(band, floorf(t * 34.f))) - 0.5f) * (0.006f + 0.020f * rev);
  float on = renderWord(f2(uv.x + gj, uv.y), w, wl, ox, oy, gh, aspect);

  // box halo: soft rectangle behind the word → the emitted glow
  float dx = fmaxf(fmaxf(ox - uv.x, uv.x - (ox + wordW)), 0.f);
  float dy = fmaxf(fmaxf(oy - uv.y, uv.y - (oy + gh)), 0.f);
  float halo = expf(-90.f * (dx * dx + dy * dy));

  tint = mix3(accent, accentD, 0.22f);
  return vis * (on * (0.55f + 0.35f * load) + 0.05f * halo);
}

// The burn: diagonal plasma rays sweeping across, white-hot core + accent
// glow, entering/leaving off-frame. Load scales the blaze.
HD float burnAt(float2 p, float t, float load, float aspect) {
  float b = 0.f;
  for (int i = 0; i < 4; i++) {
    float fi = (float)i;
    float slope = 0.28f + 0.12f * hashf(f2(fi, 4.2f));
    float phase = fractf(t * (0.035f + 0.020f * hashf(f2(fi, 7.7f))) + fi * 0.41f);
    float off = mixf(-1.6f, 1.6f, phase) * aspect;
    float d = p.x - slope * p.y - off;
    float core = expf(-520.f * d * d);
    float glow = expf(-110.f * d * d);
    float life = smoothstepf(0.f, 0.12f, phase) * smoothstepf(1.f, 0.86f, phase);
    b += life * (core + 0.09f * glow);
  }
  return b * (0.16f + 0.84f * load);
}

// ── THE FIELD — one function, host and device ─────────────────────────────

HD float3 fieldColor(float2 uv, const FieldParams& P) {
  float2 p = f2((uv.x - 0.5f) * P.aspect, uv.y - 0.5f);
  float t = P.time;

  float lum = P.surface.x * 0.299f + P.surface.y * 0.587f + P.surface.z * 0.114f;
  float night = 1.f - stepf(0.5f, lum);
  float aff = 1.f - P.reg;

  // base field
  float grad = smoothstepf(-0.9f, 0.9f, p.y + 0.15f * sinf(t * 0.03f));
  float3 col = mix3(P.paper, P.surface, grad);

  float neb = fbm2(f2(p.x * 1.6f + t * 0.008f, p.y * 1.6f - t * 0.005f));
  neb *= neb;
  col = col + night * aff * 0.045f * neb * mix3(P.accent, P.accentD, 0.5f);

  float dayNeb = fbm2(f2(p.x * 1.3f + t * 0.020f, p.y * 1.3f - t * 0.012f));
  dayNeb *= dayNeb;
  float dayNeb2 = fbm2(f2(p.x * 2.4f - t * 0.014f + 31.7f, p.y * 2.4f - t * 0.009f + 31.7f));
  col = col - f3(1, 1, 1) * ((1.f - night) * (0.050f * dayNeb + 0.022f * dayNeb2 * dayNeb2));
  col = mix3(col, col * mix3(f3(1, 1, 1), P.accent * 1.35f, 0.10f), (1.f - night) * dayNeb);

  float vig = dot2(p, p);
  col = col * (1.f - mixf(0.20f, 0.35f, night) * vig);

  // live warm-up: a working GPU lifts the whole field a touch
  col = col + night * P.load * 0.022f * mix3(P.accent, P.accentD, 0.5f);
  col = col - f3(1, 1, 1) * ((1.f - night) * P.load * 0.012f);

  // affluent: blooms + the orbital horizon
  if (aff > 0.001f) {
    float2 b1 = f2(sinf(t * 0.157f), sinf(t * 0.111f)) * 0.42f;
    float2 b2 = f2(sinf(t * 0.126f + 2.1f), sinf(t * 0.089f + 1.3f)) * 0.38f;
    float g1 = expf(-9.f * dot2(p - b1, p - b1));
    float g2 = expf(-7.f * dot2(p - b2, p - b2));
    col = col + night * aff * (0.10f * g1 * P.accent + 0.07f * g2 * P.accentD);
    col = col - f3(1, 1, 1) * ((1.f - night) * aff * (0.030f * g1 + 0.020f * g2));

    float2 hc = f2(0.f, 1.9f);
    float dHor = len2(p - hc) - 1.62f;
    float limb = expf(-55.f * fabsf(dHor));
    float atmo = expf(-6.f * fmaxf(0.f, dHor));
    float3 horizonTint = mix3(P.accent, P.accentD, 0.35f);
    col = col + night * aff * (0.09f * limb + 0.025f * atmo) * horizonTint;
    col = col - f3(1, 1, 1) * ((1.f - night) * aff * (0.10f * limb + 0.008f * atmo));

    float lightCell = floorf((p.x + t * 0.004f) * 70.f);
    float lh = hashf(f2(lightCell, 7.7f));
    float lights = smoothstepf(0.010f, 0.0f, fabsf(dHor)) * stepf(0.90f, lh) *
                   (0.6f + 0.4f * sinf(t * (0.8f + lh) + lh * 6.2832f));
    col = col + night * aff * 0.16f * lights * P.accentD;
  }

  // facility: SM-occupancy beam curtains + constellation mesh + scanlines + rain
  if (P.reg > 0.001f) {
    // beam curtains: columns rising from the floor, heights driven by live
    // GPU load, tips heating toward white with power draw
    float NCOL = 54.f;
    float ci = floorf(uv.x * NCOL);
    float cf = fractf(uv.x * NCOL);
    float ch2 = hashf(f2(ci, 23.1f));
    float wob = 0.5f + 0.5f * sinf(t * (0.7f + 1.8f * ch2) + ch2 * 6.2832f);
    float colH = (0.015f + 0.05f * ch2) + P.load * (0.40f + 0.48f * ch2) * (0.6f + 0.4f * wob);
    float yUp = 1.f - uv.y;
    float cwidth = smoothstepf(0.5f, 0.17f, fabsf(cf - 0.5f));
    float body = cwidth * (1.f - smoothstepf(colH - 0.02f, colH, yUp)) *
                 (0.35f + 0.65f * clamp01(yUp / fmaxf(colH, 1e-3f)));
    float tip = cwidth * smoothstepf(0.022f, 0.f, fabsf(yUp - colH));
    float3 tipCol = mix3(P.accentD, f3(1, 1, 1), 0.35f * P.power);
    float surge = 0.10f + 0.90f * P.load;   // idle nearly bare, inference ablaze
    col = col + night * P.reg * surge * (0.055f * body * P.accent + 0.26f * tip * tipCol);
    col = col - f3(1, 1, 1) * ((1.f - night) * P.reg * (0.045f * body + 0.10f * tip));

    const float GATE = 0.978f;
    float2 gp = p * 14.f;
    float2 cell = f2(floorf(gp.x), floorf(gp.y));
    float2 cuv = f2(fractf(gp.x) - 0.5f, fractf(gp.y) - 0.5f);

    Star s0 = starIn(cell, GATE);
    float h0 = hashf(cell);
    float pulse = 0.5f + 0.5f * sinf(t * (0.5f + h0) + h0 * 6.2832f);
    float d = len2(cuv - s0.pos);
    float core = smoothstepf(0.055f, 0.f, d);
    float glintX = smoothstepf(0.16f, 0.f, fabsf(cuv.x - s0.pos.x)) *
                   smoothstepf(0.012f, 0.f, fabsf(cuv.y - s0.pos.y));
    float glintY = smoothstepf(0.16f, 0.f, fabsf(cuv.y - s0.pos.y)) *
                   smoothstepf(0.012f, 0.f, fabsf(cuv.x - s0.pos.x));
    float star = s0.on * (core + 0.55f * (glintX + glintY)) * pulse;
    col = col + night * P.reg * 0.33f * star * P.accent;
    col = col - f3(1, 1, 1) * ((1.f - night) * P.reg * 0.22f * star);

    float mesh = 0.f;
    Star sr = starIn(cell + f2(1, 0), GATE);
    Star sd = starIn(cell + f2(0, 1), GATE);
    if (s0.on > 0.5f && sr.on > 0.5f)
      mesh += smoothstepf(0.020f, 0.f, segDist(cuv, s0.pos, sr.pos + f2(1, 0)));
    if (s0.on > 0.5f && sd.on > 0.5f)
      mesh += smoothstepf(0.020f, 0.f, segDist(cuv, s0.pos, sd.pos + f2(0, 1)));
    float meshGate = smoothstepf(0.6f, 1.0f, P.reg);
    col = col + night * meshGate * 0.05f * mesh * P.accent;
    col = col - f3(1, 1, 1) * ((1.f - night) * meshGate * 0.04f * mesh);

    float lines = 0.5f + 0.5f * sinf(uv.y * 1200.f);
    col = col - f3(1, 1, 1) * (P.reg * 0.020f * lines);
    float drift = fractf(uv.y - t * 0.125f);
    float driftLine = smoothstepf(0.012f, 0.f, fminf(drift, 1.f - drift));
    col = col + night * P.reg * 0.030f * driftLine * P.accent;
    col = col - f3(1, 1, 1) * ((1.f - night) * P.reg * 0.020f * driftLine);

    float colId = floorf(p.x * 26.f);
    float ch = hashf(f2(colId, 3.7f));
    float head = fractf(t * (0.04f + 0.11f * ch) * (1.f + 2.2f * P.load) + ch * 7.31f);
    float dCol = head - uv.y;
    float trail = smoothstepf(0.35f, 0.f, fabsf(dCol)) * stepf(0.f, dCol);
    float core2 = smoothstepf(0.45f, 0.10f, fabsf(fractf(p.x * 26.f) - 0.5f));
    float cellY = floorf(uv.y * 90.f);
    float glyph = 0.30f + 0.70f * hashf(f2(colId * 3.1f, cellY + floorf(t * (6.f + 18.f * P.load)) * 0.13f));
    float rain = trail * core2 * glyph * stepf(0.72f - 0.30f * P.load, ch);
    col = col + night * P.reg * 0.050f * rain * P.accent;
    col = col - f3(1, 1, 1) * ((1.f - night) * P.reg * 0.032f * rain);
  }

  // ── THE HOSAKA REEL — burn, kernel words, reflective floor ─────────────
  // The reference-reel motifs, facility/night only. All load-reactive: idle
  // is a quiet console, inference is the music video.
  if (P.reg > 0.001f && night > 0.5f) {
    float3 hot = mix3(P.accentD, f3(1, 1, 1), 0.55f);

    // the burn
    float burn = burnAt(p, t, P.load, P.aspect);
    col = col + P.reg * 0.030f * burn * mix3(P.accent, hot, 0.5f);

    // reflective floor: the rays echo below a horizon, mirrored + rippled
    float horizon = 0.64f;
    if (uv.y > horizon) {
      float depth = (uv.y - horizon) / (1.f - horizon);
      float my = (2.f * horizon - uv.y) - 0.5f + 0.015f * sinf(uv.x * 48.f + t * 2.2f) * depth;
      float burnR = burnAt(f2(p.x, my), t, P.load, P.aspect);
      col = col + P.reg * 0.015f * (1.f - 0.7f * depth) * burnR * mix3(P.accent, hot, 0.4f);
    }

    // the CASK6 kernel words
    float3 wtint;
    float word = kernelGlyphs(uv, t, P.aspect, P.load, wtint, P.accent, P.accentD);
    col = col + P.reg * 0.30f * word * mix3(wtint, hot, 0.10f * P.load);
  }

  // day signature: the MAAS BIOCHIP
  if (night < 0.5f) {
    float laneRow = floorf(uv.y * 30.f);
    float lh = hashf(f2(laneRow, 11.3f));
    float laneGate = stepf(0.60f - 0.15f * P.reg, lh);
    float lineD = fabsf(fractf(uv.y * 30.f) - 0.5f);
    float trace = smoothstepf(0.10f, 0.03f, lineD) * laneGate;

    col = col - f3(1, 1, 1) * (0.030f * trace);

    float dir = lh > 0.80f ? 1.f : -1.f;
    float speed = (0.06f + 0.18f * hashf(f2(laneRow, 5.1f))) * (1.f + 1.6f * P.load);
    float along = fractf(p.x * 0.5f / P.aspect + 0.5f - dir * t * speed + lh * 9.f);
    float pulse2 = smoothstepf(0.020f, 0.004f, along);
    float tail = smoothstepf(0.16f, 0.f, along) * 0.30f;
    col = mix3(col, P.accent, trace * pulse2 * 0.85f);
    col = mix3(col, P.accent, trace * tail * 0.30f);

    float colX = floorf(p.x * 22.f);
    float vh = hashf(f2(colX, laneRow));
    float2 cellUV = f2(fractf(p.x * 22.f) - 0.5f, fractf(uv.y * 30.f) - 0.5f);
    float via = stepf(0.88f, vh) * laneGate * smoothstepf(0.14f, 0.06f, len2(cellUV));
    col = col - f3(1, 1, 1) * (0.045f * via);
  }

  // the reconcile sweep
  if (P.sweep > -0.5f) {
    float ds = uv.y - P.sweep;
    float line = smoothstepf(0.005f, 0.f, fabsf(ds));
    float trailS = smoothstepf(0.15f, 0.f, -ds) * stepf(ds, 0.f);
    col = col + night * (0.22f * line + 0.05f * trailS) * P.accent;
    col = col - f3(1, 1, 1) * ((1.f - night) * (0.12f * line + 0.03f * trailS));
  }

  // grain (affluent token) + always-on dither
  col = col + f3(1, 1, 1) * ((hashf(f2(uv.x * 1920.f + fractf(t), uv.y * 1080.f + fractf(t))) - 0.5f) * P.grain);
  col = col + f3(1, 1, 1) * ((hashf(f2(uv.x * 3840.f + fractf(t * 0.37f), uv.y * 2160.f + fractf(t * 0.37f))) - 0.5f) * (1.2f / 255.f));

  return col;
}

// ── kernel + host renderer around the ONE field ───────────────────────────

static __global__ void fieldKernel(uchar4* out, int w, int h, FieldParams P) {
  int x = blockIdx.x * blockDim.x + threadIdx.x;
  int y = blockIdx.y * blockDim.y + threadIdx.y;
  if (x >= w || y >= h) return;
  float2 uv = f2((x + 0.5f) / w, (y + 0.5f) / h);
  float3 c = fieldColor(uv, P);
  out[y * w + x] = make_uchar4(
      (unsigned char)(clamp01(c.x) * 255.f + 0.5f),
      (unsigned char)(clamp01(c.y) * 255.f + 0.5f),
      (unsigned char)(clamp01(c.z) * 255.f + 0.5f), 255);
}

inline void renderHost(std::vector<uchar4>& out, int w, int h, const FieldParams& P) {
  for (int y = 0; y < h; y++)
    for (int x = 0; x < w; x++) {
      float2 uv = f2((x + 0.5f) / w, (y + 0.5f) / h);
      float3 c = fieldColor(uv, P);
      out[y * w + x] = make_uchar4(
          (unsigned char)(clamp01(c.x) * 255.f + 0.5f),
          (unsigned char)(clamp01(c.y) * 255.f + 0.5f),
          (unsigned char)(clamp01(c.z) * 255.f + 0.5f), 255);
    }
}

// ── theme.json ingestion (four hexes + register; tiny and forgiving) ──────

inline bool hexAfter(const std::string& s, const std::string& key, float3& out) {
  auto k = s.find("\"" + key + "\"");
  if (k == std::string::npos) return false;
  auto hash = s.find('#', k);
  if (hash == std::string::npos || hash + 7 > s.size()) return false;
  unsigned v = std::stoul(s.substr(hash + 1, 6), nullptr, 16);
  out = f3(((v >> 16) & 0xff) / 255.f, ((v >> 8) & 0xff) / 255.f, (v & 0xff) / 255.f);
  return true;
}

inline void loadTheme(const std::string& path, FieldParams& P) {
  std::ifstream f(path);
  if (!f) { fprintf(stderr, "wintermute-field: cannot read %s\n", path.c_str()); return; }
  std::stringstream ss; ss << f.rdbuf();
  std::string s = ss.str();
  hexAfter(s, "base00", P.surface);
  hexAfter(s, "base01", P.paper);
  hexAfter(s, "base0A", P.accent);
  hexAfter(s, "base09", P.accentD);
  auto r = s.find("\"register\"");
  if (r != std::string::npos) {
    auto colon = s.find(':', r);
    if (colon != std::string::npos) P.reg = std::stof(s.substr(colon + 1));
  }
}

inline void writePPM(const char* path, const std::vector<uchar4>& px, int w, int h) {
  FILE* f = fopen(path, "wb");
  if (!f) { perror(path); return; }
  fprintf(f, "P6\n%d %d\n255\n", w, h);
  for (auto& c : px) { fputc(c.x, f); fputc(c.y, f); fputc(c.z, f); }
  fclose(f);
}

// ── main ──────────────────────────────────────────────────────────────────

