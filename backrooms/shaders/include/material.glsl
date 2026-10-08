#ifndef BACKROOMS_MATERIAL
#define BACKROOMS_MATERIAL
float grain(vec3 p) {
  return fract(sin(dot(floor(p * 29.0), vec3(13.9898, 78.233, 37.719))) * 43758.5453);
}
vec3 paint(Hit hit, vec3 direction, float anomaly) {
  vec3 p = hit.p, n = hit.normal;
  float roomHeight = hit.room == 0 ? CORRIDOR_HEIGHT : HALL_HEIGHT;
  vec3 base = vec3(.74, .67, .35);
  float emission = 0.0;
  if (hit.material == 1) {
    vec2 uv = abs(n.x) > .5 ? p.zy : p.xy;
    vec2 tile = fract(uv * vec2(2.0, 1.4)) - .5;
    float stem = 1.0 - smoothstep(.008, .021, abs(tile.x));
    float leaf =
        1.0 - smoothstep(.012, .035, abs(abs(tile.x) + abs(tile.y * .6) - .19));
    base *= 1.0 - .09 * max(stem, leaf);
    float skirting = 1.0 - smoothstep(.17, .22, p.y);
    base = mix(base, vec3(.37, .30, .14), skirting);
  }
  if (hit.material == 2) {
    base = vec3(.42, .36, .19);
    float seam = min(abs(fract(p.x / 2.0) - .5), abs(fract(p.z / 2.0) - .5));
    base *= .93 + .07 * smoothstep(.0, .017, seam);
  }
  if (hit.material == 3) {
    base = vec3(.82, .82, .69);
    vec2 uv = hit.room == 0 ? vec2(p.x, p.z) : p.xz;
    vec2 grid = abs(fract(uv * .5) - .5);
    float edge = max(grid.x, grid.y);
    base *= mix(1.0, .66, smoothstep(.485, .495, edge));
  }
  if (hit.material == 5) {
    base = vec3(1.0, .96, .72);
    emission = 1.0;
    float divider = step(.06, abs(fract(p.z * 3.0) - .5));
    base *= .85 + .15 * divider;
  }
  if (hit.material == 4)
    base = vec3(.78, .72, .45);
  base *= .965 + .055 * grain(p);
  float ambient = .43 + .08 * n.y;
  float nearFloor = smoothstep(0.0, .5, p.y);
  float nearCeiling = smoothstep(0.0, .45, roomHeight - p.y);
  float corner = .74 + .26 * min(nearFloor, nearCeiling);
  float panelDistance = abs(mod(p.z + 1.5, 6.0) - 3.0);
  float light = .25 + .22 * exp(-panelDistance * .35);
  vec3 lit = base * (ambient + light) * corner;
  if (emission > .5)
    lit = base * 1.25;
  if (anomaly > .5) {
    lit = mix(lit, lit * vec3(.32, .63, 1.6), .85);
    if (emission > .5)
      lit = vec3(.12, .55, 1.0);
  }
  return pow(max(lit, vec3(0)), vec3(1.0 / 2.2));
}
#endif
