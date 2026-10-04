#ifndef ESCHER_FOLDING_RENDER
#define ESCHER_FOLDING_RENDER
#include <escher:folding_space.glsl>
#include <escher:folding_scene.glsl>
vec2 foldArchitecture(vec3 p) {
  p.x = mod(p.x + FOLD_WIDTH * .5, FOLD_WIDTH) - FOLD_WIDTH * .5;
  return foldingScene(p);
}
struct FoldHit {
  float stepDistance;
  float surfaceDistance;
  float material;
  vec3 source;
  vec4 sphere;
  vec3 sphereSource;
};
void foldBranch(vec3 point, vec3 p, float q, float metric, inout FoldHit hit) {
  float factor = q / metric;
  float vertical = max(-.08 - p.y, p.y - 2.85);
  if (vertical * factor >= hit.stepDistance)
    return;
  if (vertical * factor < hit.surfaceDistance) {
    vec2 material = foldArchitecture(p);
    float d = material.x * factor;
    if (d < hit.surfaceDistance) {
      hit.surfaceDistance = d;
      hit.material = material.y;
      hit.source = p;
      hit.sphere = vec4(0);
    }
    hit.stepDistance = min(hit.stepDistance, d);
  }
  for (int laneIndex = -1; laneIndex <= 1; laneIndex++) {
    float lane = float(laneIndex) * 18. * FOLD_WIDTH / 128.;
    float motion = FoldingData.z + float(laneIndex) * FOLD_BALL_SPACING / 3.;
    float x =
        floor((p.x - motion) / FOLD_BALL_SPACING + .5) * FOLD_BALL_SPACING + motion;
    float ground = laneIndex == 0 ? .10 : 0.;
    float bound = sdBox(p - vec3(x, ground + .35, lane), vec3(1.3, 1.3, 1.3));
    if (bound * factor > hit.stepDistance)
      continue;
    vec3 source = vec3(x, ground, lane);
    float size = FOLD_BALL_RADIUS * foldScale(source, FoldingData.y);
    vec3 center =
        foldPoint(source, FoldingData.y) + foldFrame(source, FoldingData.y)[1] * size;
    float d = length(point - center) - size;
    hit.stepDistance = min(hit.stepDistance, d);
    if (d < hit.surfaceDistance) {
      hit.surfaceDistance = d;
      hit.material = 4.;
      hit.source = p;
      hit.sphere = vec4(center, size);
      hit.sphereSource = source;
    }
  }
}
FoldHit foldQuery(vec3 point) {
  float domain;
  if (FoldingData.y == 0.)
    domain = abs(point.z) - FOLD_HALF_DEPTH - .15;
  else {
    vec3 centered = point + vec3(0, FOLD_RADIUS / FoldingData.y, 0);
    float latitude = FoldingData.y * (FOLD_HALF_DEPTH + .15) / FOLD_RADIUS;
    domain = abs(centered.z) * cos(latitude) - length(centered.xy) * sin(latitude);
  }
  if (domain > .0001 * FoldingScale)
    return FoldHit(domain, 1e20, 0., vec3(0), vec4(0), vec3(0));
  float q, metric;
  vec2 branch;
  vec3 p = foldUnwrap(point, FoldingData.y, q, metric, branch);
  FoldHit hit = FoldHit(1e20, 1e20, 0., p, vec4(0), vec3(0));
  foldBranch(point, p, q, metric, hit);
  if (FoldingData.y > 0.) {
    foldBranch(point, p + vec3(branch, 0.), q, metric, hit);
    foldBranch(point, p - vec3(branch, 0.), q, metric, hit);
    // Unvisited longitude branches lie outside this vertical range.
    hit.stepDistance = min(hit.stepDistance, 1.25 * branch.y * q / metric);
    hit.stepDistance = min(hit.stepDistance, .10 * FOLD_RADIUS * q / FoldingData.y);
  }
  return hit;
}
vec3 foldSurfaceNormal(vec3 p) {
  const vec2 e = vec2(.002, -.002);
  return normalize(
      e.xyy * foldArchitecture(p + e.xyy).x + e.yyx * foldArchitecture(p + e.yyx).x +
      e.yxy * foldArchitecture(p + e.yxy).x + e.xxx * foldArchitecture(p + e.xxx).x);
}
vec3 foldPaint(FoldHit hit, vec3 point, vec3 direction, float footprint) {
  vec3 base = vec3(.78, .75, .65), n;
  float ao = 1.;
  if (hit.sphere.w > 0.) {
    n = normalize(point - hit.sphere.xyz);
    mat3 frame = foldFrame(hit.sphereSource, FoldingData.y);
    vec3 local = transpose(frame) * n;
    local.xy = rotate2(local.xy,
                       abs(hit.sphereSource.z) < .1 ? FoldingData.w : FoldingSideRoll);
    float band = 1. - smoothstep(.10, .18, abs(local.x));
    base = mix(vec3(.88, .15, .025), vec3(.97, .87, .62), band);
  } else {
    vec3 raw = foldSurfaceNormal(hit.source);
    mat3 j = foldJacobian(hit.source, FoldingData.y);
    n = normalize(cross(j[1], j[2]) * raw.x + cross(j[2], j[0]) * raw.y +
                  cross(j[0], j[1]) * raw.z);
    ao = clamp(foldArchitecture(hit.source + raw * .16).x / .16, .45, 1.);
    if (hit.material == 1.)
      base = vec3(.94, .92, .82);
    if (hit.material == 2.) {
      float tile = FOLD_WIDTH / 32.;
      vec2 uv = hit.source.xz / tile;
      vec2 w = vec2(max(
          .001, footprint / max(foldScale(hit.source, FoldingData.y), 1e-6) / tile));
      vec2 integral =
          2. *
          (abs(fract((uv - w * .5) * .5) - .5) - abs(fract((uv + w * .5) * .5) - .5)) /
          w;
      base = mix(vec3(.76, .755, .66), vec3(.24, .39, .30),
                 .5 - .5 * integral.x * integral.y);
    }
    if (hit.material == 3.)
      base = vec3(.075, .20, .15);
    if (hit.material == 4.)
      base = vec3(.65, .10, .045);
    if (hit.material == 5.)
      base = vec3(.47, .33, .13);
  }
  vec3 light = normalize(FoldingLight);
  vec3 color = base * (.52 + .43 * max(dot(n, light), 0.)) * mix(.78, 1., ao);
  if (hit.material == 4. || hit.material == 5.)
    color += .18 * pow(max(dot(n, normalize(light - direction)), 0.), 55.);
  return pow(max(color, 0.), vec3(1. / 2.2));
}
vec4 renderFolding(float renderHeight, int budget) {
  vec3 direction =
      normalize(FoldingView * vec3((texCoord * 2. - 1.) / Projection, -1.));
  float distance = .02 * FoldingScale, footprint = 0.;
  bool found = false;
  FoldHit hit;
  vec3 point;
  for (int i = 0; i < budget; i++) {
    point = FoldingEye + direction * distance;
    if (distance > 1400. * FoldingScale)
      break;
    if (FoldingData.y > 0. &&
        length(point + vec3(0, FOLD_RADIUS / FoldingData.y, 0)) < 1e-5 * FoldingScale)
      break;
    hit = foldQuery(point);
    footprint = max(.0007 * FoldingScale, distance / (renderHeight * Projection.y));
    if (hit.surfaceDistance < footprint * .5) {
      found = true;
      break;
    }
    distance += max(.0003 * FoldingScale, .72 * hit.stepDistance);
  }
  vec3 sky = vec3(.91, .925, .875), color = sky;
  if (found) {
    color = foldPaint(hit, point, direction, footprint);
    float haze = 1. - exp(-pow(.003 * distance / FoldingScale, 2.));
    color = mix(color, sky, haze);
  }
  color *= 1. - .05 * dot(texCoord - .5, texCoord - .5);
  return vec4(color, 1.);
}
#endif
