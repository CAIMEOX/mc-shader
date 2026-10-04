#ifndef ESCHER_RENDER_DATA
#define ESCHER_RENDER_DATA
#include <escher:packet.glsl>
#include <escher:rotation.glsl>
#ifdef ESCHER_RENDER_VERTEX
#define ESCHER_VARYING out
#else
#define ESCHER_VARYING in
#endif
layout(location = 0) ESCHER_VARYING vec2 texCoord;
layout(location = 1) flat ESCHER_VARYING vec3 RayOrigin;
layout(location = 2) flat ESCHER_VARYING mat3 InverseView;
layout(location = 5) flat ESCHER_VARYING vec4 Lens;
layout(location = 6) flat ESCHER_VARYING float FrameReady;
layout(location = 7) flat ESCHER_VARYING vec2 Projection;
layout(location = 8) flat ESCHER_VARYING float RenderQuality;
layout(location = 9) flat ESCHER_VARYING vec4 FoldingData;
layout(location = 10) flat ESCHER_VARYING vec4 FoldingEyeAndRoll;
#define FoldingEye FoldingEyeAndRoll.xyz
#define FoldingSideRoll FoldingEyeAndRoll.w
layout(location = 11) flat ESCHER_VARYING mat3 FoldingView;
layout(location = 14) flat ESCHER_VARYING vec4 FoldingLighting;
#define FoldingScale FoldingLighting.w
#define FoldingLight FoldingLighting.xyz
vec3 worldRay(vec2 uv) {
  return normalize(InverseView * vec3((uv * 2.0 - 1.0) / Projection, -1));
}
#endif
