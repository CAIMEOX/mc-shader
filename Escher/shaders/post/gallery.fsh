#version 330
#extension GL_ARB_separate_shader_objects : require
#include <minecraft:globals.glsl>
#include <escher:render_data.glsl>
#include <escher:space.glsl>
#include <escher:distance.glsl>
#include <escher:folding_render.glsl>
layout(location = 0) out vec4 fragColor;
layout(std140) uniform Parameters {
  vec4 Values;
};

vec3 paint(vec3 p, vec3 n, vec3 direction, float material, float footprint) {
  vec3 base = vec3(.78, .75, .65);
  if (material == 1.0)
    base = vec3(.94, .92, .82);
  if (material == 2.0) {
    // Box-filtered square wave suppresses distant checker moire.
    vec2 w = vec2(max(.002, footprint));
    vec2 a = p.xz * .5;
    vec2 integral = (abs(fract(a - w * .5) - .5) - abs(fract(a + w * .5) - .5)) / w;
    float checker = .5 + .5 * integral.x * integral.y;
    base = mix(vec3(.30, .39, .26), vec3(.96, .945, .87), checker);
  }
  if (material == 3.0)
    base = vec3(.065, .20, .135);
  if (material == 4.0)
    base = vec3(.78, .095, .025);
  if (material == 5.0)
    base = vec3(.47, .33, .13);
  float diffuse = max(dot(n, normalize(vec3(-.5, .85, -.4))), 0.0);
  float ambient = .45 + .17 * n.y;
  float ao = clamp(scene(p + n * .22).x / .22, .45, 1.0);
  vec3 color = base * (ambient + .42 * diffuse) * mix(.8, 1.0, ao);
  if (material == 4.0 || material == 5.0) {
    vec3 halfway = normalize(normalize(vec3(-.5, .85, -.4)) - direction);
    color += vec3(.22) * pow(max(dot(n, halfway), 0.0), material == 4.0 ? 45.0 : 70.0);
  }
  return pow(max(color, 0.0), vec3(1.0 / 2.2));
}
void main() {
  if (FrameReady < .5 || abs(RenderQuality - Values.x) > .5) {
    fragColor = vec4(0);
    return;
  }
  float renderHeight = Values.w > 0.0 ? Values.w : ScreenSize.y;
  if (FoldingData.x > .5) {
    fragColor = renderFolding(renderHeight, int(Values.y));
    return;
  }
  float phase = RayOrigin.z / Lens.x, scale = exp(Lens.y * phase);
  vec3 origin = embed(RayOrigin), direction = worldRay(texCoord);
  direction.xy = rotate2(direction.xy, Lens.z * phase);
  float t = .025 * scale;
  vec3 p = vec3(0);
  vec2 surface = vec2(1, 0);
  float h = 1.0;
  bool hit = false;
  float metric = sqrt(1.0 + pow(Lens.z / Lens.y, 2.0)) / Lens.w;
  float footprint = 0.0;
  for (int step = 0; step < int(Values.y); step++) {
    vec3 point = origin + direction * t;
    if (point.z >= Lens.w * (1.0 - 1e-5) || t > 2e5 * scale)
      break;
    p = pullback(point, h);
    surface = scene(p);
    footprint = max(.001, t / (renderHeight * Projection.y * h));
    if (surface.x < max(.002, footprint * .45)) {
      hit = true;
      break;
    }
    // The inverse map's shear grows with distance from the axis. This
    // local metric and the relative scale cap keep thin arches traversable.
    float bound = 1.0 + length(p.xy) * metric;
    t += min(.72 * surface.x * h / bound, .12 * Lens.w * h);
  }
  vec3 sky = vec3(.925, .91, .87), color = sky;
  if (hit) {
    vec3 n = surfaceNormal(p);
    vec3 localDirection =
        vec3(rotate2(direction.xy, -Lens.z * log(h) / Lens.y), direction.z);
    color = paint(p, n, localDirection, surface.y, footprint);
    float haze = 1.0 - exp(-.002 * t / scale);
    color = mix(color, sky, haze);
  }
  color *= 1.0 - .055 * dot(texCoord - .5, texCoord - .5);
  fragColor = vec4(color, 1);
}
