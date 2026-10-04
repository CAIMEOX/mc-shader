#ifndef SIGNAL_CODEC
#define SIGNAL_CODEC
vec4 encodeUint(uint value) {
  return vec4(value >> 24u, (value >> 16u) & 255u, (value >> 8u) & 255u, value & 255u) /
         255.0;
}
uint decodeUint(vec4 value) {
  uvec4 b = uvec4(round(value * 255.0));
  return (b.r << 24u) | (b.g << 16u) | (b.b << 8u) | b.a;
}
uint rgbWord(vec3 value) {
  uvec3 b = uvec3(round(value * 255.0));
  return (b.r << 16u) | (b.g << 8u) | b.b;
}
vec3 wordRgb(uint word) {
  return vec3((word >> 16u) & 255u, (word >> 8u) & 255u, word & 255u) / 255.0;
}
uint digest(uint value) {
  value ^= 0x53a9f17du;
  value = (value ^ (value >> 16u)) * 0x7feb352du;
  value = (value ^ (value >> 15u)) * 0x846ca68bu;
  return value ^ (value >> 16u);
}
uint resultSymbol(uint word, uint hash) {
  uint mode = (word >> 16u) & 3u;
  return mode >= 2u ? (hash & (mode == 3u ? 3u : 1u)) : mode;
}
#endif
