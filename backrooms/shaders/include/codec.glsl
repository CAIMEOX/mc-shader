#ifndef BACKROOMS_CODEC
#define BACKROOMS_CODEC
vec4 encodeUint(uint value) {
  return vec4(value >> 24u, (value >> 16u) & 255u, (value >> 8u) & 255u, value & 255u) /
         255.0;
}
uint decodeUint(vec4 value) {
  uvec4 b = uvec4(round(value * 255.0));
  return (b.r << 24u) | (b.g << 16u) | (b.b << 8u) | b.a;
}
vec4 encodeFloat(float value) {
  return encodeUint(floatBitsToUint(value));
}
float decodeFloat(vec4 value) {
  return uintBitsToFloat(decodeUint(value));
}
uint rgbWord(vec3 rgb) {
  uvec3 b = uvec3(round(rgb * 255.0));
  return (b.r << 16u) | (b.g << 8u) | b.b;
}
vec3 wordRgb(uint word) {
  return vec3((word >> 16u) & 255u, (word >> 8u) & 255u, word & 255u) / 255.0;
}
uint encodeFloat24(float x) {
  return (floatBitsToUint(x) + 128u) >> 8u;
}
float decodeFloat24(uint x) {
  return uintBitsToFloat(x << 8u);
}
#endif
