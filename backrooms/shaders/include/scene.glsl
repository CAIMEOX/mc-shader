#ifndef BACKROOMS_SCENE
#define BACKROOMS_SCENE
#include <backrooms:geometry.glsl>
struct Hit {
  float t;
  vec3 p;
  vec3 normal;
  int material;
  int room;
  int primary;
};
Hit emptyHit(int room) {
  return Hit(1e5, vec3(0), vec3(0, 1, 0), 1, room, 1);
}
void planeHit(inout Hit h, vec3 o, vec3 d, int axis, float coordinate, vec3 normal,
              int material, int room) {
  if (abs(d[axis]) < 1e-7)
    return;
  float t = (coordinate - o[axis]) / d[axis];
  if (t > .001 && t < h.t)
    h = Hit(t, o + t * d, normal, material, room, material);
}
void boxHit(inout Hit h, vec3 o, vec3 d, vec3 lo, vec3 hi, int material, int room) {
  vec3 safe = d;
  for (int i = 0; i < 3; i++)
    if (abs(safe[i]) < 1e-8)
      safe[i] = safe[i] < 0.0 ? -1e-8 : 1e-8;
  vec3 a = (lo - o) / safe, b = (hi - o) / safe;
  vec3 mn = min(a, b), mx = max(a, b);
  float near = max(mn.x, max(mn.y, mn.z)), far = min(mx.x, min(mx.y, mx.z));
  if (far < max(near, .001))
    return;
  float t = near > .001 ? near : far;
  if (t >= h.t)
    return;
  vec3 p = o + t * d, n = vec3(0);
  vec3 center = (lo + hi) * .5, size = (hi - lo) * .5;
  vec3 relative = (p - center) / max(size, vec3(.001));
  int axis = abs(relative.x) > abs(relative.y) ? 0 : 1;
  if (abs(relative.z) > abs(relative[axis]))
    axis = 2;
  n[axis] = relative[axis] > 0.0 ? 1.0 : -1.0;
  h = Hit(t, p, n, material, room, material);
}
bool doorOpening(vec3 p, int room) {
  float z = room == 0 ? mod(p.z, ROOM_PERIOD) - 12.0 : p.z;
  return abs(z) < DOOR_HALF_WIDTH && p.y >= 0.0 && p.y < DOOR_HEIGHT;
}
int surfaceMaterial(vec3 p, int room, int material) {
  if (material != 3)
    return material;
  vec3 q = p;
  q.y = room == 0 ? CORRIDOR_HEIGHT : HALL_HEIGHT;
  if (room == 0)
    q.z = mod(q.z, ROOM_PERIOD);
  if (room == 0) {
    for (int i = 0; i < CORRIDOR_LIGHT_COUNT; i++)
      if (all(greaterThanEqual(q, CORRIDOR_LIGHT_LOWER[i])) &&
          all(lessThan(q, CORRIDOR_LIGHT_UPPER[i])))
        return 5;
  } else {
    for (int i = 0; i < HALL_LIGHT_COUNT; i++)
      if (all(greaterThanEqual(q, HALL_LIGHT_LOWER[i])) &&
          all(lessThan(q, HALL_LIGHT_UPPER[i])))
        return 5;
  }
  return material;
}
Hit traceRoom(vec3 o, vec3 d, int room) {
  Hit h = emptyHit(room);
  if (room == 0) {
    planeHit(h, o, d, 1, 0.0, vec3(0, 1, 0), 2, room);
    planeHit(h, o, d, 1, CORRIDOR_HEIGHT, vec3(0, -1, 0), 3, room);
    planeHit(h, o, d, 0, -CORRIDOR_HALF_WIDTH, vec3(1, 0, 0), 1, room);
    if (h.material == 1 && h.normal.x > .5) {
      float z = mod(h.p.z, ROOM_PERIOD);
      if (z > 4.5 && z < 7.5 && h.p.y > 1.0 && h.p.y < 3.5) {
        h.material = 6;
        h.primary = 6;
      }
    }
    Hit east = emptyHit(room);
    planeHit(east, o, d, 0, CORRIDOR_HALF_WIDTH, vec3(-1, 0, 0), 1, room);
    if (doorOpening(east.p, room)) {
      east.material = 7;
      east.primary = 7;
    }
    if (east.t < h.t)
      h = east;
  } else {
    for (int i = 0; i < HALL_BOX_COUNT; i++)
      boxHit(h, o, d, HALL_LOWER[i], HALL_UPPER[i], HALL_MATERIAL[i], room);
    Hit door = emptyHit(room);
    if (d.x < -.00001)
      planeHit(door, o, d, 0, -HALL_HALF_WIDTH, vec3(1, 0, 0), 7, room);
    if (doorOpening(door.p, room) && door.t < h.t)
      h = door;
  }
  h.material = surfaceMaterial(h.p, room, h.material);
  h.primary = h.material;
  return h;
}
Hit traceSpace(vec3 origin, vec3 direction, int room) {
  Hit first = traceRoom(origin, direction, room);
  if (first.material != 7)
    return first;
  vec3 mapped = first.p;
  int target = 1 - room;
  if (room == 0) {
    mapped.z = mod(mapped.z, ROOM_PERIOD);
    mapped += PORTAL_SHIFT;
  } else
    mapped -= PORTAL_SHIFT;
  Hit next = traceRoom(mapped + direction * .002, direction, target);
  next.t += first.t + .002;
  next.primary = 7;
  return next;
}
#endif
