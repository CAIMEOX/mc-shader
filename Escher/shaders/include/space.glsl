#ifndef ESCHER_SPACE
#define ESCHER_SPACE
vec2 rotate2(vec2 p, float angle) {
  float c = cos(angle), s = sin(angle);
  return mat2(c, s, -s, c) * p;
}
vec3 embed(vec3 p) {
  float u = p.z / Lens.x, h = exp(Lens.y * u);
  return vec3(rotate2(p.xy, Lens.z * u) * h, Lens.w * (1.0 - h));
}
vec3 pullback(vec3 p, out float h) {
  h = max(1e-8, 1.0 - p.z / Lens.w);
  float u = log(h) / Lens.y;
  return vec3(rotate2(p.xy, -Lens.z * u) / h, u * Lens.x);
}
#endif
