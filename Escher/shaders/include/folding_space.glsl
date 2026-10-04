#ifndef ESCHER_FOLDING_SPACE
#define ESCHER_FOLDING_SPACE
#include <escher:folding_settings.glsl>
float foldSinc(float x) {
  float x2 = x * x;
  return abs(x) < .001 ? 1. - x2 / 6. + x2 * x2 / 120. : sin(x) / x;
}
float foldExprel(float x) {
  return abs(x) < .001 ? 1. + x * .5 + x * x / 6. + x * x * x / 24. : (exp(x) - 1.) / x;
}
float foldLog1p(float x) {
  return abs(x) < .001 ? x - x * x * .5 + x * x * x / 3. - x * x * x * x * .25
                       : log(1. + x);
}
vec3 foldPoint(vec3 p, float t) {
  if (t == 0.)
    return p;
  float h = p.y - t * FOLD_HEIGHT * p.x / FOLD_WIDTH, u = t * h / FOLD_RADIUS,
        q = exp(u);
  float m = p.y / FOLD_HEIGHT - p.x / FOLD_WIDTH;
  float a = t * p.x / FOLD_RADIUS + t * t * FOLD_TURN * m, b = t * p.z / FOLD_RADIUS;
  float loss = -2. * pow(sin(b * .5), 2.) - 2. * cos(b) * pow(sin(a * .5), 2.);
  return vec3(q * cos(b) * (p.x + FOLD_RADIUS * t * FOLD_TURN * m) * foldSinc(a),
              h * foldExprel(u) + FOLD_RADIUS * q * loss / t, q * p.z * foldSinc(b));
}
float foldScale(vec3 p, float t) {
  return exp(t * (p.y - t * FOLD_HEIGHT * p.x / FOLD_WIDTH) / FOLD_RADIUS);
}
mat3 foldJacobian(vec3 p, float t) {
  float a = t * p.x / FOLD_RADIUS +
            t * t * FOLD_TURN * (p.y / FOLD_HEIGHT - p.x / FOLD_WIDTH),
        b = t * p.z / FOLD_RADIUS;
  float q = foldScale(p, t);
  vec3 radial = vec3(cos(b) * sin(a), cos(b) * cos(a), sin(b));
  vec3 east = vec3(cos(a), -sin(a), 0),
       north = vec3(-sin(b) * sin(a), -sin(b) * cos(a), cos(b));
  return mat3(q * cos(b) * (1. - t * FOLD_RADIUS * FOLD_TURN / FOLD_WIDTH) * east -
                  q * t * FOLD_HEIGHT / FOLD_WIDTH * radial,
              q * radial +
                  q * cos(b) * FOLD_RADIUS * t * FOLD_TURN / FOLD_HEIGHT * east,
              q * north);
}
mat3 foldFrame(vec3 p, float t) {
  mat3 j = foldJacobian(p, t);
  vec3 forward = normalize(j[0]), up = normalize(cross(j[2], j[0]));
  return mat3(forward, up, normalize(cross(forward, up)));
}
vec3 foldSourceCamera(vec3 p, float period) {
  return vec3((p.z / period - .5) * FOLD_WIDTH, p.y + 5., -p.x);
}
// Return the inverse branch closest to the building's vertical slab.
vec3 foldUnwrap(vec3 p, float t, out float q, out float metric, out vec2 branch) {
  if (t == 0.) {
    q = 1.;
    metric = 1.;
    branch = vec2(0);
    return p;
  }
  float k = t / FOLD_RADIUS;
  vec3 centered = vec3(k * p.x, 1. + k * p.y, k * p.z);
  q = max(length(centered), 1e-8);
  float u = k * (2. * p.y + k * dot(p, p));
  float h = abs(u) < .001 ? .5 * foldLog1p(u) / k : log(q) / k;
  float b = asin(clamp(centered.z / q, -1., 1.));
  float a = atan(centered.x, centered.y) - t * t * FOLD_TURN * h / FOLD_HEIGHT;
  a = atan(sin(a), cos(a));
  float A = 1. - t * FOLD_RADIUS * FOLD_TURN / FOLD_WIDTH,
        B = -t * FOLD_HEIGHT / FOLD_WIDTH,
        K = FOLD_RADIUS * t * FOLD_TURN / FOLD_HEIGHT, D = A - K * B;
  float x = a / (k * D), y = h + t * FOLD_HEIGHT * x / FOLD_WIDTH;
  branch = vec2(FOLD_WIDTH / (t * D), FOLD_HEIGHT / D);
  float n = floor((1.385 - y) / branch.y + .5);
  float cb = max(abs(cos(b)), .02);
  float trace = (1. + B * B) / (cb * cb * D * D) + (K * K + A * A) / (D * D);
  float determinant = 1. / (cb * D);
  metric = max(1., sqrt(.5 * (trace + sqrt(max(0., trace * trace - 4. * determinant *
                                                                       determinant)))));
  return vec3(x + n * branch.x, y + n * branch.y, b / k);
}
#endif
