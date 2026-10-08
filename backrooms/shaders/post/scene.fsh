#version 330
#extension GL_ARB_separate_shader_objects : require
#include <backrooms:render_data.glsl>
#include <backrooms:scene.glsl>
#include <backrooms:material.glsl>
uniform sampler2D MainSampler;
uniform sampler2D WorldDepthSampler;
layout(location = 0) out vec4 fragColor;
void main() {
  if (FrameReady < .5) {
    fragColor = vec4(0);
    return;
  }
  vec3 ray = worldRay(texCoord);
  Hit h = traceSpace(RayOrigin, ray, int(RoomId));
  float firstDistance = h.t;
  if (h.primary == 7)
    firstDistance = (RoomId < .5 ? CORRIDOR_HALF_WIDTH - RayOrigin.x
                                 : -HALL_HALF_WIDTH - RayOrigin.x) /
                    ray.x;
  vec3 color;
  if (h.material == 6) {
    firstDistance = h.t;
    vec3 reflected = reflect(ray, h.normal);
    Hit reflection = traceSpace(h.p + h.normal * .004, reflected, h.room);
    color = paint(reflection, reflected, MirrorState);
    vec2 panel = vec2(mod(h.p.z, ROOM_PERIOD) - 6.0, h.p.y - 2.25);
    float edge = max(abs(panel.x) / 1.5, abs(panel.y) / 1.25);
    color = mix(color * .91, vec3(.22, .18, .10), smoothstep(.91, .96, edge));
    color += .025 * vec3(.6, .7, .6);
  } else
    color = paint(h, ray, 0.0);
  float haze = 1.0 - exp(-.007 * h.t);
  color = mix(color, vec3(.48, .46, .33), min(haze, .65));
  ivec2 size = textureSize(MainSampler, 0);
  ivec2 pixel = clamp(ivec2(texCoord * vec2(size)), ivec2(0), size - 1);
  vec2 depthUv = (vec2(pixel) + .5) / vec2(size);
  float depth = texelFetch(WorldDepthSampler, pixel, 0).r;
  float denominator = DepthProjection.z * depth + DepthProjection.x;
  float viewDistance = denominator > 1e-9 ? DepthProjection.y / denominator : 1e7;
  float nativeDistance = viewDistance / max(.0001, -viewRay(depthUv).z);
  int semantic = h.primary;
  if (depth > 1e-8 && nativeDistance > .025) {
    bool foreground = nativeDistance < .75;
    if (!foreground && nativeDistance + 0.075 < firstDistance) {
      vec3 depthRay = worldRay(depthUv);
      Hit matching = traceSpace(RayOrigin, depthRay, int(RoomId));
      float limit = matching.t;
      if (matching.primary == 7)
        limit = (RoomId < .5 ? CORRIDOR_HALF_WIDTH - RayOrigin.x
                             : -HALL_HALF_WIDTH - RayOrigin.x) /
                depthRay.x;
      foreground = nativeDistance + 0.075 < limit;
    }
    if (foreground) {
      color = texelFetch(MainSampler, pixel, 0).rgb;
      semantic = 8;
    }
  }
  fragColor = vec4(color, float(semantic) / 255.0);
}
