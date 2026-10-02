float m = 0.;
for (int j = 0; j < 64; j++)
  m = max(m, abs(scalar(Input0Sampler, i * 64 + j)));
outValue = m / 127.;
