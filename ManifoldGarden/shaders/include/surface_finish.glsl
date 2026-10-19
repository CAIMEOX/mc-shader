#ifndef MANIFOLD_SURFACE_FINISH
#define MANIFOLD_SURFACE_FINISH

void stageBoxFinishPeriod(vec3 p, vec3 n, vec3 lo, vec3 hi, float footprint,
                          float period, inout float nearest, inout vec4 detail) {
  vec3 local = mod(p - (lo + hi) * .5 + period * .5, period) - period * .5;
  vec3 gap = (hi - lo) * .5 - abs(local);
  if (min(gap.x, min(gap.y, gap.z)) < -.04)
    return;
  vec3 a = abs(n);
  vec3 face = a.x > a.y && a.x > a.z ? vec3(1, 0, 0)
                                     : (a.y > a.z ? vec3(0, 1, 0) : vec3(0, 0, 1));
  float plane = abs(dot(gap, face));
  vec3 tangents = mix(gap, vec3(1e4), face);
  float edge = max(0.0, min(tangents.x, min(tangents.y, tangents.z)));
  if (plane < nearest - .001 || (abs(plane - nearest) < .001 && edge > detail.w)) {
    nearest = plane;
    vec3 bevel = 1.0 - smoothstep(vec3(0), vec3(.045 + footprint), max(gap, vec3(0)));
    vec3 weights = max(face, bevel);
    detail = vec4(normalize(sign(local) * weights), edge);
  }
}
void stageBoxFinish(vec3 p, vec3 n, vec3 lo, vec3 hi, float footprint,
                    inout float nearest, inout vec4 detail) {
  stageBoxFinishPeriod(p, n, lo, hi, footprint, 32.0, nearest, detail);
}
#endif
