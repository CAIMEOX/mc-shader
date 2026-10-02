#ifndef FLAME_RENDER_DATA
#define FLAME_RENDER_DATA
#include <flame:packet.glsl>
#include <flame:rotation.glsl>
#include <flame:grid.glsl>
#ifdef FLAME_RENDER_VERTEX
#define FLAME_VARYING out
#else
#define FLAME_VARYING in
#endif
layout(location = 0) FLAME_VARYING vec2 texCoord;
layout(location = 1) flat FLAME_VARYING vec3 RayOrigin;
layout(location = 2) flat FLAME_VARYING mat3 InverseView;
layout(location = 5) flat FLAME_VARYING mat4 InverseProjection;
layout(location = 9) flat FLAME_VARYING float FrameReady;
layout(location = 10) flat FLAME_VARYING float SimulationTime;
float projectionBias() {
#ifdef RENDERPEARL_DEPTH_IS_ZERO_TO_ONE
  return 0.0;
#else
  return 1.0;
#endif
}
float clipDepth(float d) {
#ifdef RENDERPEARL_DEPTH_IS_ZERO_TO_ONE
  return d;
#else
  return d * 2.0 - 1.0;
#endif
}
vec3 viewPoint(vec2 uv, float d) {
  vec4 p = InverseProjection * vec4(uv * 2.0 - 1.0, clipDepth(d), 1);
  return p.xyz / p.w;
}
vec3 worldRay(vec2 uv) {
  return normalize(InverseView * viewPoint(uv, 1.0));
}
float sceneDistance(sampler2D depth, vec2 uv) {
  float d = texture(depth, uv).r;
  return d > 0.0 ? length(viewPoint(uv, d)) : 1000.0;
}
#endif
