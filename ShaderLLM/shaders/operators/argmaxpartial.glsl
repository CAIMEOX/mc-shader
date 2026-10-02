// argmax pair reduction; tie resolves lowest ID
float best = -1e30;
int chosen = -1;
for (int j = 0; j < 256; j++) {
  int k = (i / 2) * 256 + j;
  if (k >= n)
    break;
  float v = scalar(Input0Sampler, k);
  if (v > best) {
    best = v;
    chosen = k;
  }
}
fragColor = i % 2 == 0 ? packF(best) : packU(uint(chosen));
return;
