#ifndef MANIFOLD_RAY_BOX
#define MANIFOLD_RAY_BOX

vec2 rayBoxInterval(vec3 origin, vec3 inverseRay, vec3 lo, vec3 hi) {
  vec3 a = (lo - origin) * inverseRay, b = (hi - origin) * inverseRay;
  vec3 nearPlane = min(a, b), farPlane = max(a, b);
  return vec2(max(nearPlane.x, max(nearPlane.y, nearPlane.z)),
              min(farPlane.x, min(farPlane.y, farPlane.z)));
}

bool rayBoxCandidate(vec3 origin, vec3 inverseRay, vec3 lo, vec3 hi, float start,
                     float end) {
  vec2 interval = rayBoxInterval(origin, inverseRay, lo, hi);
  return max(start, interval.x) <= min(end, interval.y);
}

void rayBoxHit(vec3 origin, vec3 inverseRay, vec3 lo, vec3 hi, float start, float end,
               inout float nearest, inout vec3 normal) {
  vec3 nearPlane = min((lo - origin) * inverseRay, (hi - origin) * inverseRay);
  vec2 interval = rayBoxInterval(origin, inverseRay, lo, hi);
  float hit = max(start, interval.x);
  if (hit > min(end, interval.y) || hit >= nearest)
    return;
  nearest = hit;
  int axis = nearPlane.x > nearPlane.y && nearPlane.x > nearPlane.z
                 ? 0
                 : (nearPlane.y > nearPlane.z ? 1 : 2);
  normal = vec3(0);
  normal[axis] = -sign(inverseRay[axis]);
}
#endif
