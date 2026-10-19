#ifndef MANIFOLD_JOINERY_MATERIAL
#define MANIFOLD_JOINERY_MATERIAL
#include <manifold:joinery_style.glsl>
float joineryHash(vec2 p) {
  vec3 q = fract(vec3(p.xyx) * .1031);
  q += dot(q, q.yzx + 33.33);
  return fract((q.x + q.y) * q.z);
}
float joineryNoise(vec2 p) {
  vec2 cell = floor(p), f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
  return mix(mix(joineryHash(cell), joineryHash(cell + vec2(1, 0)), f.x),
             mix(joineryHash(cell + vec2(0, 1)), joineryHash(cell + 1.0), f.x), f.y);
}
struct JoinerySurface {
  vec3 albedo;
  vec3 normal;
  float roughness;
  int member;
};
JoinerySurface joinerySurface(vec3 p, vec3 n, float footprint) {
  int id = joineryMember(p), axis = JOINERY_AXIS[id];
  vec3 local = mod(p - joineryShift(id) + .5, 64.0) - .5;
  float along = local[axis], u = local[(axis + 1) % 3], v = local[(axis + 2) % 3];
  vec2 crossSection = vec2(u, v) - vec2(27.5 + float(id % 2) * 8.0, 31.5);
  vec2 drift = vec2(joineryNoise(vec2(along * .045, float(id) * 3.7)),
                    joineryNoise(vec2(along * .031 + 21.0, float(id) * 2.3))) -
               .5;
  float radius = length((crossSection + drift * .35) * vec2(1.0, .88));
  float growth = radius * 17.0 + joineryNoise(crossSection * .48) * 7.0 +
                 joineryNoise(crossSection * 1.4) * 1.2;
  float end = abs(n[axis]);
  float rings = pow(.5 + .5 * sin(growth), 10.0) * exp(-footprint * 16.0);
  float fibre = joineryNoise(vec2(radius * 36.0, along * .22 + float(id) * 5.0)) - .5;
  float field = joineryNoise(vec2(u * .19, v * .19) + float(id) * 1.71) - .5;
  vec3 wood = joineryPalette(id);
  vec3 color = wood * (1.0 + field * .035 - rings * mix(.024, .038, end) +
                       fibre * .026 * exp(-footprint * 45.0));
  vec3 shadingNormal = n;
  vec3 grid = abs(mod(local + .5 + 2.0, 4.0) - 2.0);
  grid = mix(grid, vec3(10), greaterThan(abs(n), vec3(.8)));
  float edge = min(grid.x, min(grid.y, grid.z));
  float bevelWeight = 1.0 - smoothstep(.055, .14, footprint);
  if (edge < .09 && bevelWeight > 0.0) {
    vec3 point = p + n * .04, gradient = vec3(0);
    for (int a = 0; a < 3; a++) {
      vec3 step = vec3(0);
      step[a] = .065;
      gradient[a] = joineryDistance(point + step) - joineryDistance(point - step);
    }
    if (dot(gradient, gradient) > 1e-10)
      shadingNormal = normalize(mix(n, normalize(gradient), bevelWeight));
  }
  float roughness = .56 + field * .06;
  if (end > .8 && min(abs(along - 7.5), abs(along - 55.5)) < .06) {
    float nearest = 10.0;
    vec2 offset = vec2(0);
    for (int dot = 0; dot < 6; dot++) {
      if (dot > id)
        break;
      vec2 centre = vec2(float(dot % 3) - 1.0, float(dot / 3) - .5) * .72;
      vec2 delta = crossSection - centre;
      if (length(delta) < nearest) {
        nearest = length(delta);
        offset = delta;
      }
    }
    float detail = exp(-footprint * 6.0);
    float mask = (1.0 - smoothstep(.12, .17 + footprint, nearest)) * detail;
    vec3 inlay = joineryHome(id) ? vec3(.40, .52, .43) : wood * .58;
    color = mix(color, inlay, mask * .9);
    float rim =
        (smoothstep(.055, .11, nearest) - smoothstep(.11, .18, nearest)) * detail;
    vec3 insetNormal = shadingNormal;
    insetNormal[(axis + 1) % 3] -= offset.x * 1.8 * rim;
    insetNormal[(axis + 2) % 3] -= offset.y * 1.8 * rim;
    shadingNormal = normalize(insetNormal);
    roughness = mix(roughness, .68, mask);
  }
  if (int(JoineryFocus.x) == id)
    color *= 1.035;
  if (id == JoineryBlocker)
    color = mix(color, wood * .86, .12);
  return JoinerySurface(color, shadingNormal, roughness, id);
}
#endif
