// W8A8 activation groups, C roundf semantics
int group = i / 17, part = i % 17;
float scale = scalar(Input1Sampler, group);
if (part == 16) {
  fragColor = packF(scale);
  return;
}
vec4 q;
for (int j = 0; j < 4; j++) {
  float v = scale == 0. ? 0. : scalar(Input0Sampler, group * 64 + part * 4 + j) / scale;
  q[j] = sign(v) * floor(abs(v) + .5) + 128.;
}
fragColor = q / 255.;
return;
