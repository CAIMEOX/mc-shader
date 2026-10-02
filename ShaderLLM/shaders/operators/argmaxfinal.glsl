
float best = -1e30;
uint chosen = 0u;
for (int j = 0; j < n; j++) {
  float v = scalar(Input0Sampler, j * 2);
  uint id = integer(Input0Sampler, j * 2 + 1);
  if (v > best || (v == best && id < chosen)) {
    best = v;
    chosen = id;
  }
}
fragColor = i == 0 ? packF(best) : packU(chosen);
return;
