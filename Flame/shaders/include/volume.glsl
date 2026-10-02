#ifndef FLAME_VOLUME
#define FLAME_VOLUME
#include <flame:render_data.glsl>
uniform sampler2D FieldSampler;
uniform sampler2D BoundsSampler;
vec4 volumeField(vec3 position) {
  vec3 p = position / CELL_SIZE - .5;
  ivec3 a = ivec3(floor(p));
  vec3 f = fract(p);
  vec4 sum = vec4(0);
  for (int z = 0; z < 2; z++)
    for (int y = 0; y < 2; y++)
      for (int x = 0; x < 2; x++) {
        ivec3 q = a + ivec3(x, y, z);
        if (!inGrid(q))
          continue;
        vec3 w = mix(1.0 - f, f, vec3(x, y, z));
        sum += texelFetch(FieldSampler, address(cellIndex(q)), 0) * w.x * w.y * w.z;
      }
  return sum;
}
bool volumeInterval(vec3 origin, vec3 ray, float depth, out float nearT,
                    out float farT) {
  vec3 safeRay = mix(ray, vec3(1e-7), lessThan(abs(ray), vec3(1e-7)));
  vec3 a = -origin / safeRay, b = (vec3(REGION) - origin) / safeRay;
  vec3 lo = min(a, b), hi = max(a, b);
  nearT = max(0.0, max(lo.x, max(lo.y, lo.z)));
  farT = min(depth, min(hi.x, min(hi.y, hi.z)));
  return farT > nearT;
}
vec3 fireColor(float temperature) {
  float t = clamp((temperature - 550.0) / 1550.0, 0.0, 1.0);
  vec3 c = mix(vec3(1, .035, .001), vec3(1, .4, .035), smoothstep(0.0, .45, t));
  c = mix(c, vec3(1, .87, .35), smoothstep(.35, .75, t));
  return mix(c, vec3(1, .98, .83), smoothstep(.68, 1.0, t));
}
float noiseHash(ivec3 p) {
  uint h = uint(p.x) * 1597334677u ^ uint(p.y) * 3812015801u ^ uint(p.z) * 2798796415u;
  h = (h ^ (h >> 16u)) * 2246822519u;
  h ^= h >> 13u;
  return float(h & 65535u) / 65535.0;
}
float noise3(vec3 p) {
  ivec3 a = ivec3(floor(p));
  vec3 f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
  return mix(
      mix(mix(noiseHash(a), noiseHash(a + ivec3(1, 0, 0)), f.x),
          mix(noiseHash(a + ivec3(0, 1, 0)), noiseHash(a + ivec3(1, 1, 0)), f.x), f.y),
      mix(mix(noiseHash(a + ivec3(0, 0, 1)), noiseHash(a + ivec3(1, 0, 1)), f.x),
          mix(noiseHash(a + ivec3(0, 1, 1)), noiseHash(a + ivec3(1, 1, 1)), f.x), f.y),
      f.z);
}
vec4 traceVolume(vec2 uv, float depth, bool detailed) {
  vec3 ray = worldRay(uv);
  float start, end;
  if (!volumeInterval(RayOrigin, ray, depth, start, end))
    return vec4(0);
  float stepSize = max(detailed ? .17 : .4, (end - start) / (detailed ? 96.0 : 32.0)),
        t = start + .35 * stepSize, transmittance = 1.0;
  vec3 emission = vec3(0);
  for (int iteration = 0;
       iteration < (detailed ? 160 : 64) && t < end && transmittance > .015;
       iteration++) {
    vec3 point = RayOrigin + ray * t;
    ivec3 coarse = clamp(ivec3(floor(point / (CELL_SIZE * 4.0))), ivec3(0), COARSE - 1);
    int index = coarse.x + COARSE.x * (coarse.y + COARSE.y * coarse.z);
    if (texelFetch(BoundsSampler, ivec2(index % 16, index / 16), 0).r < .001) {
      vec3 boundary = (vec3(coarse) + step(vec3(0), ray)) * (CELL_SIZE * 4.0);
      vec3 distances =
          (boundary - point) / mix(ray, vec3(1e-7), lessThan(abs(ray), vec3(1e-7)));
      t += max(.015, min(distances.x, min(distances.y, distances.z)) + .005);
      continue;
    }
    vec4 field = volumeField(point);
    float ds = min(stepSize, end - t);
    float detail = .5;
    if (detailed) {
      vec3 flow = point * 1.35 - vec3(.13, .95, .09) * SimulationTime;
      detail = .65 * noise3(flow) + .35 * noise3(flow * 2.03 + vec3(11.7, 3.4, 9.1));
    }
    float fade = smoothstep(0.0, 1.3, float(REGION.y) - point.y);
    float temperature = AMBIENT + 2000.0 * field.r,
          smoke = 2.0 * field.g * (.6 + .8 * detail) * fade;
    float flame = field.b * smoothstep(0.0, .14, field.b - .07 - .25 * detail) * fade;
    float extinction = 1.3 * smoke + .35 * flame, attenuation = exp(-extinction * ds);
    vec3 ambientScatter =
        mix(vec3(.11, .13, .15), vec3(.30, .34, .40), exp(-smoke * 1.5));
    float incandescentSoot = smoke * smoothstep(900.0, 1500.0, temperature) *
                             smoothstep(.15, .65, detail + .3 * field.r);
    vec3 source = fireColor(AMBIENT + .68 * (temperature - AMBIENT)) *
                      (flame * 8.0 + incandescentSoot * 3.5) *
                      pow(clamp((temperature - 420.0) / 1350.0, 0.0, 1.3), 1.3) +
                  ambientScatter * smoke * 1.3;
    emission += transmittance * source *
                (extinction > .001 ? (1.0 - attenuation) / extinction : ds);
    transmittance *= attenuation;
    t += ds;
  }
  return vec4(emission / (1.0 + emission), 1.0 - transmittance);
}
#endif
