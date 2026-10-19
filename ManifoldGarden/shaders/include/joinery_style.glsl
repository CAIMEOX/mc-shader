#ifndef MANIFOLD_JOINERY_STYLE
#define MANIFOLD_JOINERY_STYLE
const vec3 JOINERY_LIGHT = normalize(vec3(-.48, .78, .40));
const vec3 JOINERY_SKY = vec3(.58, .61, .59);
vec3 joineryPalette(int id) {
  const vec3 colors[6] =
      vec3[](vec3(.69, .57, .42), vec3(.77, .70, .57), vec3(.64, .49, .40),
             vec3(.60, .55, .46), vec3(.53, .43, .35), vec3(.73, .63, .48));
  return colors[clamp(id, 0, 5)];
}
float joineryDepthBlend(float travel) {
  return .76 * (1.0 - exp(-max(travel - 24.0, 0.0) * .0036));
}
vec3 joineryAtmosphere(vec3 color, vec3 albedo, vec3 normal, float travel) {
  vec3 distant = mix(JOINERY_SKY, albedo, .18) * (.94 + .06 * normal.y);
  return mix(color, distant, joineryDepthBlend(travel));
}
vec2 joineryEncodeDepth(float depth) {
  float value = floor(clamp(depth * 100.0, 0.0, 65535.0) + .5);
  return vec2(floor(value / 256.0), mod(value, 256.0)) / 255.0;
}
float joineryDecodeDepth(vec2 value) {
  return dot(floor(value * 255.0 + .5), vec2(256.0, 1.0)) * .01;
}
#endif
