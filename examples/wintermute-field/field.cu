// wintermute-field CLI — see field.cuh for the field itself.
#include "field.cuh"

int main(int argc, char** argv) {
  int w = 1920, h = 1080, frames = 1;
  bool bench = false, verify = false, cpu = false;
  float spin = 0.f;
  std::string out = "field.ppm", theme;

  FieldParams P{};
  P.time = 8.f; P.reg = 1.f; P.grain = 0.02f; P.sweep = -1.f; P.load = 0.f; P.power = 0.f;
  P.surface = f3(0.098f, 0.110f, 0.122f);   // #191c1f carbon
  P.paper   = f3(0.118f, 0.137f, 0.161f);   // #1e2329
  P.accent  = f3(0.322f, 0.647f, 1.f);      // #52a5ff
  P.accentD = f3(0.502f, 0.824f, 1.f);      // #80d2ff

  for (int i = 1; i < argc; i++) {
    std::string a = argv[i];
    auto next = [&]() -> const char* { return i + 1 < argc ? argv[++i] : ""; };
    if (a == "--size") sscanf(next(), "%dx%d", &w, &h);
    else if (a == "--time") P.time = atof(next());
    else if (a == "--reg") P.reg = atof(next());
    else if (a == "--sweep") P.sweep = atof(next());
    else if (a == "--load") P.load = atof(next());
    else if (a == "--power") P.power = atof(next());
    else if (a == "--frames") frames = atoi(next());
    else if (a == "--out") out = next();
    else if (a == "--scene") P.scene = std::string(next()) == "eyes" ? 1 : 0;
    else if (a == "--spin") spin = atof(next());
    else if (a == "--theme") theme = next();
    else if (a == "--bench") bench = true;
    else if (a == "--verify") verify = true;
    else if (a == "--cpu") cpu = true;
  }
  if (!theme.empty()) loadTheme(theme, P);
  // --spin THETA: rotate the whole palette about the gray axis (radians) —
  // the color spinor as a knob, and the visual test of spinColor itself
  if (spin != 0.f) {
    P.surface = spinColor(P.surface, spin);
    P.paper   = spinColor(P.paper, spin);
    P.accent  = spinColor(P.accent, spin);
    P.accentD = spinColor(P.accentD, spin);
  }
  P.aspect = (float)w / h;

  // --cpu: the same field, host-side — renders anywhere (including under
  // driver/runtime skew), and doubles as the reference half of --verify.
  if (cpu) {
    std::vector<uchar4> px(size_t(w) * h);
    auto t0 = std::chrono::steady_clock::now();
    renderHost(px, w, h, P);
    auto t1 = std::chrono::steady_clock::now();
    writePPM(out.c_str(), px, w, h);
    printf("// wintermute-field // CPU // %dx%d // %.0f ms // %s //\n", w, h,
           std::chrono::duration<double, std::milli>(t1 - t0).count(), out.c_str());
    return 0;
  }

  thrust::device_vector<uchar4> dbuf(size_t(w) * h);
  dim3 block(16, 16), grid((w + 15) / 16, (h + 15) / 16);

  if (bench) {
    // warmup + timed run
    fieldKernel<<<grid, block>>>(thrust::raw_pointer_cast(dbuf.data()), w, h, P);
    cudaDeviceSynchronize();
    const int N = 200;
    auto t0 = std::chrono::steady_clock::now();
    for (int i = 0; i < N; i++) {
      P.time += 1.f / 30.f;
      fieldKernel<<<grid, block>>>(thrust::raw_pointer_cast(dbuf.data()), w, h, P);
    }
    cudaDeviceSynchronize();
    auto t1 = std::chrono::steady_clock::now();
    double ms = std::chrono::duration<double, std::milli>(t1 - t0).count() / N;
    printf("// wintermute-field // %dx%d // %.3f ms/frame // %.1f Mpix/s // %.0f fps possible //\n",
           w, h, ms, (double)w * h / ms / 1e3, 1000.0 / ms);
    return 0;
  }

  if (verify) {
    fieldKernel<<<grid, block>>>(thrust::raw_pointer_cast(dbuf.data()), w, h, P);
    cudaDeviceSynchronize();
    thrust::host_vector<uchar4> gpu = dbuf;
    std::vector<uchar4> cpu(size_t(w) * h);
    renderHost(cpu, w, h, P);
    int maxDiff = 0; long long sum = 0;
    for (size_t i = 0; i < cpu.size(); i++) {
      int d = abs((int)cpu[i].x - gpu[i].x);
      d = std::max(d, abs((int)cpu[i].y - gpu[i].y));
      d = std::max(d, abs((int)cpu[i].z - gpu[i].z));
      maxDiff = std::max(maxDiff, d); sum += d;
    }
    printf("// conformance // cpu vs gpu // max channel diff %d // mean %.4f //\n",
           maxDiff, (double)sum / cpu.size());
    return maxDiff <= 2 ? 0 : 1;   // ulp-level trig divergence tolerance
  }

  for (int fidx = 0; fidx < frames; fidx++) {
    fieldKernel<<<grid, block>>>(thrust::raw_pointer_cast(dbuf.data()), w, h, P);
    cudaDeviceSynchronize();
    thrust::host_vector<uchar4> hbuf = dbuf;
    std::vector<uchar4> px(hbuf.begin(), hbuf.end());
    char path[512];
    if (frames > 1) snprintf(path, sizeof path, "%s.%03d.ppm", out.c_str(), fidx);
    else snprintf(path, sizeof path, "%s", out.c_str());
    writePPM(path, px, w, h);
    P.time += 1.f / 30.f;
  }
  printf("// wintermute-field // wrote %d frame(s) // %dx%d // reg %.2f //\n", frames, w, h, P.reg);
  return 0;
}
