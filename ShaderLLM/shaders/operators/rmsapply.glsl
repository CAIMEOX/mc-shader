
float ss = 0.;
for (int j = 0; j < n / 32; j++)
  ss += scalar(Input1Sampler, j);
outValue = scalar(Input0Sampler, i) * inversesqrt(ss / float(n) + RMS_EPS) *
           scalar(NormsSampler, b + i);
