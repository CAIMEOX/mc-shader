#ifndef MANIFOLD_RINGS_MATERIAL
#define MANIFOLD_RINGS_MATERIAL
#include <minecraft:globals.glsl>

vec3 ringsPalette(int id) {
  vec3 g = RINGS_GRAVITY[id];
  if (g.y > .5)
    return vec3(.09, .48, .68);
  if (g.x < -.5)
    return vec3(.89, .43, .11);
  if (g.z > .5)
    return vec3(.28, .64, .40);
  if (g.y < -.5)
    return vec3(.84, .72, .22);
  if (g.x > .5)
    return vec3(.73, .28, .51);
  return vec3(.46, .36, .72);
}
bool ringsSurface(vec3 p, vec3 n, float footprint, out vec3 color) {
  if (Level < 1.5)
    return false;
  for (int i = 0; i < OBJECT_COUNT; i++) {
    vec3 q = ringsOffset(p, ringsCube(i));
    if (ringsPhase(i) != 1 && max(abs(q.x), max(abs(q.y), abs(q.z))) < .53) {
      bool energized = dot(-gravityBasis(int(GravityData.y))[1], RINGS_GRAVITY[i]) > .5;
      color = cubeEnamel(q, n, RINGS_GRAVITY[i], ringsPalette(i), energized, footprint);
      return true;
    }
  }
  for (int i = 0; i < SOCKET_COUNT; i++) {
    int id = RINGS_SOCKET_CUBE[i];
    vec3 g = RINGS_GRAVITY[id];
    vec3 q = ringsOffset(p, RINGS_SOCKET[i] + g * .5);
    float plane = abs(dot(q, g));
    vec3 t = abs(q * (vec3(1) - abs(g)));
    float extent = max(t.x, max(t.y, t.z));
    if (plane < .035 && extent < .49) {
      float line = smoothstep(.29, .32, extent);
      float occupied = length(ringsOffset(ringsCube(id), RINGS_SOCKET[i])) < .1 &&
                               ringsPhase(id) != 1
                           ? 1.0
                           : .0;
      color = mix(ringsPalette(id) * .28, ringsPalette(id) * 1.35, line);
      color += occupied * .22;
      return true;
    }
  }
  vec3 q = mod(p, 64.0);
  float blueLine = abs(q.z - 4.0);
  float amberLine = abs(q.y - 3.0);
  float greenLine = abs(q.y - 3.0);
  int id = -1;
  if (abs(n.y) > .8 && (q.y < .6 || q.y > 63.4) && q.x > 7.0 && q.x < 44.5 &&
      blueLine < .09)
    id = 0;
  if (abs(n.x) > .8 && q.z > 8.0 && q.z < 21.0 && amberLine < .09)
    id = 1;
  if (abs(n.z) > .8 && abs(q.z - 28.5) < .06 && q.x > 20.0 && q.x < 56.0 &&
      greenLine < .09)
    id = 2;
  if (id >= 0) {
    float powered =
        id == 0
            ? RingsData.y
            : (id == 1
                   ? RingsData.z
                   : float(ringsPhase(2) != 1 &&
                           length(ringsOffset(ringsCube(2), RINGS_SOCKET[2])) < .1));
    float flow = .7 + .3 * sin((q.x + q.y + q.z) * 3.0 - GameTime * 1200.0 * 2.0);
    color = ringsPalette(id) * mix(.4, 1.2 * flow, max(powered, RingsData.w));
    return true;
  }
  if (RingsData.w > .5 && q.x > 27.0 && q.x < 49.0 && q.y > 11.0 && q.y < 43.0 &&
      q.z > 9.0 && q.z < 31.0) {
    color = mix(vec3(.91, .95, .88), vec3(.44, .74, .55),
                .25 + .15 * sin(q.y * .6 - GameTime * 1200.0));
    return true;
  }
  return false;
}

bool ringsHeld(vec2 uv, out vec4 color) {
  if (Level < 1.5 || RingsData.x < 0.0)
    return false;
  int id = int(RingsData.x);
  if (id >= OBJECT_COUNT)
    return false;
  mat3 rotation = heldCubeRotation();
  vec3 origin = transpose(rotation) * -HELD_CUBE_CENTRE;
  vec3 direction = transpose(rotation) * viewRay(uv);
  vec3 inv = 1.0 / (direction + vec3(1e-7));
  vec3 a = (-vec3(.22) - origin) * inv, b = (vec3(.22) - origin) * inv;
  vec3 lo = min(a, b), hi = max(a, b);
  float near = max(lo.x, max(lo.y, lo.z)), far = min(hi.x, min(hi.y, hi.z));
  if (near < 0.0 || far < near)
    return false;
  vec3 p = origin + direction * near;
  vec3 n = normalize(sign(p) * step(vec3(.2199), abs(p)));
  color = vec4(cubeEnamel(p / .44, n, RINGS_GRAVITY[id], ringsPalette(id), true, .002) *
                   (.78 + .2 * dot(rotation * n, normalize(vec3(-.3, .8, .6)))),
               1.0);
  return true;
}

bool ringsPreview(vec2 uv, float depth, out vec4 color) {
  if (Level < 1.5 || RingsData.x < 0.0 || (PreviewWord & 262144u) == 0u)
    return false;
  vec3 centre =
      vec3(PreviewWord & 63u, (PreviewWord >> 6u) & 63u, (PreviewWord >> 12u) & 63u);
  centre = RayOrigin + ringsOffset(centre, RayOrigin);
  vec3 origin = RayOrigin - centre, direction = worldRay(uv),
       inv = 1.0 / (direction + vec3(1e-7));
  vec3 a = (-vec3(.502) - origin) * inv, b = (vec3(.502) - origin) * inv;
  vec3 lo = min(a, b), hi = max(a, b);
  float near = max(lo.x, max(lo.y, lo.z)), far = min(hi.x, min(hi.y, hi.z));
  if (near < 0.0 || far < near || near > depth + .04)
    return false;
  vec3 edge = abs(origin + direction * near);
  float count = step(.473, edge.x) + step(.473, edge.y) + step(.473, edge.z);
  if (count < 1.5)
    return false;
  color = vec4(mix(ringsPalette(int(RingsData.x)), vec3(1), .3), 1);
  return true;
}
#endif
