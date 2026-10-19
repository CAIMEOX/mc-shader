#ifndef MANIFOLD_CUBE_MATERIAL
#define MANIFOLD_CUBE_MATERIAL

vec3 cubeEnamel(vec3 p, vec3 n, vec3 gravity, vec3 base, bool energized,
                float footprint) {
  vec3 up = -gravity;
  bool axial = abs(dot(up, n)) > .8;
  vec3 vertical = axial ? (abs(gravity.y) > .5 ? vec3(0, 0, 1) : vec3(0, 1, 0)) : up;
  vec3 right = normalize(cross(vertical, n));
  vec2 uv = vec2(dot(p, right), dot(p, vertical));
  float aa = max(.002, footprint);
  float border = max(abs(uv.x), abs(uv.y));
  float frame = smoothstep(.405 - aa, .445 + aa, border);
  float lip = 1.0 - smoothstep(.006, .017 + aa, abs(border - .39));
  float chevron = 1.0 - smoothstep(max(0.0, .023 - aa), .047 + aa,
                                   abs(uv.y + .18 - abs(uv.x) * .65));
  float shape = chevron * (1.0 - smoothstep(.19 - aa, .23 + aa, abs(uv.x)));
  if (axial) {
    float radius = length(uv);
    float ring = 1.0 - smoothstep(max(0.0, .014 - aa), .026 + aa, abs(radius - .17));
    float centre;
    if (dot(up, n) > 0.0) {
      float diagonal = abs(abs(uv.x) - abs(uv.y)) * .70710678;
      centre = (1.0 - smoothstep(max(0.0, .014 - aa), .026 + aa, diagonal)) *
               (1.0 - smoothstep(.15 - aa, .18 + aa, radius));
    } else {
      centre = 1.0 - smoothstep(.045 - aa, .065 + aa, radius);
    }
    shape = max(ring, centre);
  }
  vec3 enamel = base * (energized ? 1.0 : .87) * (1.0 - lip * .16);
  vec3 ceramic = energized ? vec3(.97, .965, .91) : vec3(.87, .91, .90);
  return mix(enamel, ceramic, max(frame, shape));
}

const vec3 HELD_CUBE_CENTRE = vec3(.48, -.32, -1.1);
mat3 heldCubeRotation() {
  return transpose(InverseView);
}
#endif
