#ifndef MANIFOLD_JOINERY_ILLUMINATION
#define MANIFOLD_JOINERY_ILLUMINATION
#include <manifold:joinery_style.glsl>
float joineryVisibility(vec3 p, vec3 normal) {
  if (dot(normal, JOINERY_LIGHT) <= .015)
    return 1.0;
  vec3 origin = p + normal * .035, hitNormal;
  float hit;
  if (joineryTrace(origin, JOINERY_LIGHT, 48.0, hit, hitNormal))
    return smoothstep(28.0, 48.0, hit);
  if (RenderQuality < .5)
    return 1.0;
  // Distance to the neighboring geometry gives a continuous penumbra around the
  // exact central shadow ray. The finite light horizon fades smoothly.
  float visibility = 1.0, travel = .12;
  for (int step = 0; step < 12 && travel < 48.0; step++) {
    float distance = joineryDistance(origin + JOINERY_LIGHT * travel);
    float cone = smoothstep(0.0, 1.0, 12.0 * max(distance, 0.0) / travel);
    visibility = min(visibility, mix(cone, 1.0, smoothstep(28.0, 48.0, travel)));
    travel += clamp(distance, .06, 8.0);
  }
  return visibility;
}
vec2 joineryIllumination(vec3 p, vec3 normal) {
  float occlusion = 0.0;
  const float radius[3] = float[](.16, .65, 1.8);
  const float weight[3] = float[](.30, .40, .30);
  for (int i = 0; i < 3; i++)
    occlusion +=
        weight[i] *
        clamp(1.0 - joineryDistance(p + normal * radius[i]) / radius[i], 0.0, 1.0);
  return vec2(joineryVisibility(p, normal), clamp(1.0 - .82 * occlusion, .22, 1.0));
}
#endif
