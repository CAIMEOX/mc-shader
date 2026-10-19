#ifndef MANIFOLD_RINGS_TRACE
#define MANIFOLD_RINGS_TRACE

// Traverse periodic cells in ray order. Each cell uses the compiled solid BVH.
bool ringsTrace(vec3 origin, vec3 direction, float limit, out float travel,
                out vec3 normal) {
  vec3 inverseRay = 1.0 / mix(direction, vec3(1e-20), equal(direction, vec3(0)));
  vec3 cell = floor((origin + .5) / 64.0);
  vec3 step = sign(direction);
  vec3 boundary =
      cell * 64.0 + mix(vec3(-.5), vec3(63.5), greaterThanEqual(direction, vec3(0)));
  vec3 next = (boundary - origin) * inverseRay;
  vec3 delta = 64.0 * abs(inverseRay);
  float start = .01;
  travel = limit + 1.0;
  normal = vec3(0, 1, 0);
  for (int i = 0; i < 36 && start <= limit; i++) {
    float end = min(limit, min(next.x, min(next.y, next.z)));
    vec3 local = origin - cell * 64.0;
    ringsTraceCell(local, inverseRay, start, end, travel, normal);
    for (int cube = 0; cube < OBJECT_COUNT; cube++)
      if (ringsPhase(cube) != 1) {
        vec3 centre = ringsCube(cube);
        rayBoxHit(local, inverseRay, centre - .5, centre + .5, start, end, travel,
                  normal);
      }
    if (travel <= end)
      return true;
    if (end >= limit)
      break;
    vec3 crossed = vec3(lessThanEqual(next, vec3(end + 1e-5)));
    cell += crossed * step;
    next += crossed * delta;
    start = end;
  }
  return false;
}
#endif
