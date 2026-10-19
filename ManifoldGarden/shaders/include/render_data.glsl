#ifndef MANIFOLD_RENDER_DATA
#define MANIFOLD_RENDER_DATA
#include <manifold:packet.glsl>
#include <manifold:rotation.glsl>
#include <manifold:camera.glsl>
#ifdef MANIFOLD_RENDER_VERTEX
#define MANIFOLD_VARYING out
#else
#define MANIFOLD_VARYING in
#endif
layout(location = 0) MANIFOLD_VARYING vec2 texCoord;
layout(location = 1) flat MANIFOLD_VARYING vec3 RayOrigin;
layout(location = 2) flat MANIFOLD_VARYING mat3 InverseView;
layout(location = 5) flat MANIFOLD_VARYING float FrameReady;
layout(location = 6) flat MANIFOLD_VARYING vec2 Projection;
layout(location = 7) flat MANIFOLD_VARYING float RenderQuality;
layout(location = 8) flat MANIFOLD_VARYING vec4 GravityData;
// Mode and active native room slot.
layout(location = 9) flat MANIFOLD_VARYING vec2 HybridData;
layout(location = 10) flat MANIFOLD_VARYING vec3 DepthProjection;
layout(location = 11) flat MANIFOLD_VARYING mat4 InverseProjection;
// Active scene identifier.
layout(location = 15) flat MANIFOLD_VARYING float Level;
layout(location = 16) flat MANIFOLD_VARYING vec3 WindowOrigin;
layout(location = 17) flat MANIFOLD_VARYING vec4 RingsData;
#ifndef MANIFOLD_RENDER_VERTEX
uniform sampler2D PacketSampler;
#endif
layout(location = 18) flat MANIFOLD_VARYING uvec4 ObjectCache0;
layout(location = 19) flat MANIFOLD_VARYING uvec4 ObjectCache1;
layout(location = 20) flat MANIFOLD_VARYING uint PreviewWord;
layout(location = 21) flat MANIFOLD_VARYING vec4 JoineryMotion;
layout(location = 22) flat MANIFOLD_VARYING vec4 JoineryFocus;
layout(location = 23) flat MANIFOLD_VARYING int JoineryBlocker;
vec3 viewRay(vec2 uv) {
  return normalize(projectionPoint(InverseProjection, uv, 1.0) -
                   projectionEye(InverseProjection));
}
vec3 worldRay(vec2 uv) {
  return normalize(InverseView * viewRay(uv));
}
vec3 nativeViewOffset(vec2 uv, float depth) {
  return projectionPoint(InverseProjection, uv, depth) -
         projectionEye(InverseProjection);
}
vec3 nativeWorldPoint(vec2 uv, float depth) {
  return RayOrigin + InverseView * nativeViewOffset(uv, depth);
}
#endif
