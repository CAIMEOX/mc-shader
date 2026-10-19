#ifndef MANIFOLD_JOINERY_LIGHTMAP
#define MANIFOLD_JOINERY_LIGHTMAP
#include <manifold:joinery_style.glsl>
uniform sampler2D JoineryLightSampler;
// Depth-weighted interpolation keeps the light field on its receiving surface.
vec2 joineryLightAt(vec2 uv, float travel) {
  ivec2 size = textureSize(JoineryLightSampler, 0);
  vec2 q = uv * vec2(size) - .5, fraction = fract(q);
  ivec2 origin = ivec2(floor(q));
  vec2 result = vec2(0);
  float weights = 0.0;
  for (int y = 0; y < 2; y++)
    for (int x = 0; x < 2; x++) {
      vec4 sampleLight = texelFetch(JoineryLightSampler,
                                    clamp(origin + ivec2(x, y), ivec2(0), size - 1), 0);
      float distance = joineryDecodeDepth(sampleLight.ba);
      float weight = (x == 0 ? 1.0 - fraction.x : fraction.x) *
                     (y == 0 ? 1.0 - fraction.y : fraction.y);
      weight *= exp(-abs(distance - travel) / max(.18, travel * .016));
      result += sampleLight.rg * weight;
      weights += weight;
    }
  return weights > 1e-4 ? result / weights : vec2(1);
}
#endif
