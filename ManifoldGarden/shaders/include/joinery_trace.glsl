bool joineryTrace(vec3 origin, vec3 direction, float limit, out float travel,
                  out vec3 normal) {
  vec3 inv = mix(vec3(-1), vec3(1), greaterThanEqual(direction, vec3(0))) /
             max(abs(direction), vec3(1e-8));
  vec3 cell = floor((origin + .5) / 64.0), step = sign(direction);
  vec3 boundary =
      cell * 64.0 + mix(vec3(-.5), vec3(63.5), greaterThanEqual(direction, vec3(0)));
  vec3 next = (boundary - origin) * inv, delta = 64.0 * abs(inv);
  float start = .01;
  travel = limit + 1.0;
  normal = vec3(0, 1, 0);
  for (int i = 0; i < 36 && start <= limit; i++) {
    float end = min(limit, min(next.x, min(next.y, next.z)));
    joineryTraceCell(origin - cell * 64.0, inv, start, end, travel, normal);
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
