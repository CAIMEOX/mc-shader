#ifndef FLAME_ROTATION
#define FLAME_ROTATION
vec3 rotateVector(vec4 q, vec3 p) {
  return p + 2.0 * cross(q.xyz, cross(q.xyz, p) + q.w * p);
}
vec4 basisQuaternion(mat3 m) {
  float trace = m[0][0] + m[1][1] + m[2][2];
  vec4 q;
  float s;
  if (trace > 0.0) {
    s = 2.0 * sqrt(1.0 + trace);
    q = vec4((m[1][2] - m[2][1]) / s, (m[2][0] - m[0][2]) / s, (m[0][1] - m[1][0]) / s,
             s * .25);
  } else if (m[0][0] > m[1][1] && m[0][0] > m[2][2]) {
    s = 2.0 * sqrt(1.0 + m[0][0] - m[1][1] - m[2][2]);
    q = vec4(s * .25, (m[1][0] + m[0][1]) / s, (m[2][0] + m[0][2]) / s,
             (m[1][2] - m[2][1]) / s);
  } else if (m[1][1] > m[2][2]) {
    s = 2.0 * sqrt(1.0 + m[1][1] - m[0][0] - m[2][2]);
    q = vec4((m[1][0] + m[0][1]) / s, s * .25, (m[2][1] + m[1][2]) / s,
             (m[2][0] - m[0][2]) / s);
  } else {
    s = 2.0 * sqrt(1.0 + m[2][2] - m[0][0] - m[1][1]);
    q = vec4((m[2][0] + m[0][2]) / s, (m[2][1] + m[1][2]) / s, s * .25,
             (m[0][1] - m[1][0]) / s);
  }
  return normalize(q);
}
uvec2 encodeRotation(vec4 q) {
  int omitted = 0;
  for (int i = 1; i < 4; i++)
    if (abs(q[i]) > abs(q[omitted]))
      omitted = i;
  if (q[omitted] < 0.0)
    q = -q;
  uvec3 v;
  int j = 0;
  for (int i = 0; i < 4; i++)
    if (i != omitted)
      v[j++] = uint(round(clamp(q[i] * sqrt(2.0) + 1.0, 0.0, 2.0) * 16383.5));
  return uvec2((v.x << 9u) | (v.y >> 6u),
               ((v.y & 63u) << 18u) | (v.z << 3u) | (uint(omitted) << 1u) | 1u);
}
vec4 decodeRotation(uvec2 w) {
  int omitted = int((w.y >> 1u) & 3u);
  uvec3 v = uvec3(w.x >> 9u, ((w.x & 511u) << 6u) | (w.y >> 18u), (w.y >> 3u) & 32767u);
  vec3 small = (vec3(v) / 16383.5 - 1.0) / sqrt(2.0);
  vec4 q;
  int j = 0;
  for (int i = 0; i < 4; i++)
    q[i] = i == omitted ? sqrt(max(0.0, 1.0 - dot(small, small))) : small[j++];
  return normalize(q);
}
#endif
