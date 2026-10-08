#ifndef BACKROOMS_RENDER_DATA
#define BACKROOMS_RENDER_DATA
#include <backrooms:packet.glsl>
#include <backrooms:rotation.glsl>
#ifdef BACKROOMS_RENDER_VERTEX
#define BACKROOMS_VARYING out
#else
#define BACKROOMS_VARYING in
#endif
layout(location = 0) BACKROOMS_VARYING vec2 texCoord;
layout(location = 1) flat BACKROOMS_VARYING vec3 RayOrigin;
layout(location = 2) flat BACKROOMS_VARYING mat3 InverseView;
layout(location = 5) flat BACKROOMS_VARYING vec2 Projection;
layout(location = 6) flat BACKROOMS_VARYING vec3 DepthProjection;
layout(location = 7) flat BACKROOMS_VARYING float FrameReady;
layout(location = 8) flat BACKROOMS_VARYING float RoomId;
layout(location = 9) flat BACKROOMS_VARYING float MirrorState;
vec3 viewRay(vec2 uv) {
  return normalize(vec3((uv * 2.0 - 1.0) / Projection, -1));
}
vec3 worldRay(vec2 uv) {
  return InverseView * viewRay(uv);
}
#endif
