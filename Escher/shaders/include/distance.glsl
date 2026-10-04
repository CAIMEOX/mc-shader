vec2 nearest(vec2 a, vec2 b) {
  return a.x < b.x ? a : b;
}
float sdBox(vec3 p, vec3 size) {
  vec3 q = abs(p) - size;
  return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0);
}
float sdArch(vec3 p, float radius, float thickness, float depth) {
  float radial = abs(length(p.yz) - (radius + thickness * .5)) - thickness * .5;
  float dr = p.y < 0.0 ? length(vec2(p.y, max(0.0, max(radius - abs(p.z),
                                                       abs(p.z) - radius - thickness))))
                       : max(radial, -p.y);
  vec2 q = vec2(abs(p.x) - depth, dr);
  return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);
}
#include <escher:scene.glsl>
vec3 surfaceNormal(vec3 p) {
  const vec2 e = vec2(.003, -.003);
  return normalize(e.xyy * scene(p + e.xyy).x + e.yyx * scene(p + e.yyx).x +
                   e.yxy * scene(p + e.yxy).x + e.xxx * scene(p + e.xxx).x);
}
