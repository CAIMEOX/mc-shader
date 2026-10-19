#include <manifold:gravity_settings.glsl>
#include <manifold:hybrid_render.glsl>
#include <manifold:architecture_material.glsl>

vec3 gravityNormal(vec3 p) {
  const float h = .001;
  vec3 gradient = vec3(sceneGeometryDistance(p + vec3(h, 0, 0)) -
                           sceneGeometryDistance(p - vec3(h, 0, 0)),
                       sceneGeometryDistance(p + vec3(0, h, 0)) -
                           sceneGeometryDistance(p - vec3(0, h, 0)),
                       sceneGeometryDistance(p + vec3(0, 0, h)) -
                           sceneGeometryDistance(p - vec3(0, 0, h)));
  return dot(gradient, gradient) > 1e-12 ? normalize(gradient) : vec3(0, 1, 0);
}

bool traceArchitecture(vec3 origin, vec3 direction, float height, int steps, out vec3 p,
                       out float travel) {
  if (Level > .5) {
    vec3 normal;
    bool hit = exactSceneTrace(origin, direction, 650.0, travel, normal);
    p = origin + travel * direction;
    return hit;
  }
  p = origin;
  travel = .01;
  vec2 nativeInterval = nativeWindowInterval(origin, direction);
  bool nativeWindowCovered = nativeStageMode();
  if (nativeWindowCovered && insideNativeWindow(origin, 0.0))
    travel = max(travel, nativeInterval.y + .004);
  bool hit = false;
  for (int i = 0; i < steps; i++) {
    p = origin + travel * direction;
    if (nativeWindowCovered && insideNativeWindow(p, 0.0)) {
      travel = max(travel + .004, nativeInterval.y + .004);
      continue;
    }
    float distance = sceneGeometryDistance(p);
    float epsilon = max(.001, travel / (height * Projection.y) * .35);
    if (distance < epsilon) {
      hit = true;
      break;
    }
    travel += max(.001, distance * .85);
    if (travel > 650.0)
      break;
  }
  if (hit)
    p -= gravityNormal(p) * sceneGeometryDistance(p);
  return hit;
}

vec4 renderGravity(float height, int steps) {
  vec3 direction = worldRay(texCoord), p, n;
  float travel;
  bool hit;
  if (Level > .5) {
    hit = exactSceneTrace(RayOrigin, direction, 650.0, travel, n);
    p = RayOrigin + travel * direction;
  } else {
    hit = traceArchitecture(RayOrigin, direction, height, steps, p, travel);
    n = hit ? gravityNormal(p) : vec3(0, 1, 0);
  }
  vec3 color = architectureSky();
  if (hit) {
    float ao = Level > .5 && Level < 1.5
                   ? 1.0
                   : clamp(sceneGeometryDistance(p + n * .45) / .45, .35, 1.0);
    color = architectureSurface(p, n, travel, height, ao, texCoord);
  }
  // The reticle follows the viewport; the architecture follows the gravity frame.
  vec2 pixel = (texCoord - .5) * vec2(height * Projection.y / Projection.x, height);
  if (!nativeStageMode() && ((abs(pixel.x) < .7 && abs(pixel.y) < 3.5) ||
                             (abs(pixel.y) < .7 && abs(pixel.x) < 3.5)))
    color = mix(color,
                Level > .5 && Level < 1.5
                    ? vec3(.52, .53, .49)
                    : (GravityData.z > .5 ? vec3(.9, .43, .20) : vec3(.04, .2, .20)),
                .75);
  return vec4(color, 1);
}
