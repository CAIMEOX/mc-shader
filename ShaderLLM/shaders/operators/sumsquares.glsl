// RMS norm; one reduction per group, then combine
for (int j = 0; j < 32; j++) {
  float v = scalar(Input0Sampler, i * 32 + j);
  outValue += v * v;
}
