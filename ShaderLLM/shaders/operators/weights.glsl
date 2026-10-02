float gemv(int row, int cols) {
  float result = 0.;
  for (int g = 0; g < cols / 64; g++) {
    uint wb = (uint(row) * uint(cols / 64) + uint(g)) * 17u;
    int xb = g * 17;
    int sum = 0;
    for (int j = 0; j < 16; j++) {
      ivec4 w = ivec4(round(weight(wb + uint(j)) * 255.)) - 128;
      ivec4 x = ivec4(round(at(Input0Sampler, xb + j) * 255.)) - 128;
      sum += w.x * x.x + w.y * x.y + w.z * x.z + w.w * x.w;
    }
    result += float(sum) * unpackF(weight(wb + 16u)) * scalar(Input0Sampler, xb + 16);
  }
  return result;
}
