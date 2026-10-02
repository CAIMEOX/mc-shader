uint unpackU(vec4 c) {
  uvec4 b = uvec4(round(c * 255.));
  return (b.r << 24) | (b.g << 16) | (b.b << 8) | b.a;
}
vec4 packU(uint u) {
  return vec4((u >> 24) & 255u, (u >> 16) & 255u, (u >> 8) & 255u, u & 255u) / 255.;
}
float unpackF(vec4 c) {
  return uintBitsToFloat(unpackU(c));
}
vec4 packF(float f) {
  return packU(floatBitsToUint(f));
}
vec4 at(sampler2D s, int i) {
  ivec2 n = textureSize(s, 0);
  return texelFetch(s, ivec2(i % n.x, i / n.x), 0);
}
float scalar(sampler2D s, int i) {
  return unpackF(at(s, i));
}
uint integer(sampler2D s, int i) {
  return unpackU(at(s, i));
}
