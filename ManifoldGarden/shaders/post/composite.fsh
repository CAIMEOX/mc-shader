#version 330
#extension GL_ARB_separate_shader_objects : require
#include <manifold:render_data.glsl>
#include <manifold:gravity_settings.glsl>
#include <manifold:hybrid_render.glsl>
#include <manifold:architecture_material.glsl>
uniform sampler2D MainSampler;
uniform sampler2D DepthSampler;
uniform sampler2D Scene0Sampler;
uniform sampler2D Scene1Sampler;
uniform sampler2D Scene2Sampler;
uniform sampler2D Scene3Sampler;
uniform sampler2D HistorySampler;
layout(location = 0) out vec4 fragColor;
vec4 reconstruct(sampler2D source, vec2 uv) {
  vec2 q = uv * vec2(textureSize(source, 0)) - .5;
  ivec2 a = ivec2(floor(q)), maximum = textureSize(source, 0) - 1;
  vec2 f = fract(q);
  return mix(mix(texelFetch(source, clamp(a, ivec2(0), maximum), 0),
                 texelFetch(source, clamp(a + ivec2(1, 0), ivec2(0), maximum), 0), f.x),
             mix(texelFetch(source, clamp(a + ivec2(0, 1), ivec2(0), maximum), 0),
                 texelFetch(source, clamp(a + ivec2(1, 1), ivec2(0), maximum), 0), f.x),
             f.y);
}
void main() {
  ivec2 p = ivec2(gl_FragCoord.xy), size = textureSize(MainSampler, 0);
  if (FrameReady > .5) {
    vec2 uv = (vec2(p) + .5) / vec2(size);
    // A retained packet and its depth were captured together. Present their
    // complete frame until the next camera packet arrives.
    if (texelFetch(PacketSampler, ivec2(0), 0).a < .9) {
      fragColor = texture(HistorySampler, uv);
      return;
    }
    if (ringsHeld(uv, fragColor))
      return;
    if (ringsPreview(uv, nativeRayDistance(texelFetch(DepthSampler, p, 0).r, uv),
                     fragColor))
      return;
    if (nativePixel(DepthSampler, uv)) {
      vec3 surface = nativeDepthPoint(DepthSampler, p);
      float ambient;
      vec3 normal = nativeSurfaceNormal(DepthSampler, p, ambient);
      fragColor = vec4(architectureSurface(surface, normal, length(surface - RayOrigin),
                                           float(size.y), ambient, uv),
                       1.0);
      return;
    }
    uint quality = bits(PacketSampler, FIELD_QUALITY, 2);
    if (quality == 0u)
      fragColor = reconstruct(Scene0Sampler, uv);
    else if (quality == 1u)
      fragColor = reconstruct(Scene1Sampler, uv);
    else if (quality == 2u)
      fragColor = reconstruct(Scene2Sampler, uv);
    else
      fragColor = reconstruct(Scene3Sampler, uv);
  } else {
    if (p.y == size.y - 1 && p.x < PACKET_SIZE.x)
      p.y--;
    fragColor = texelFetch(MainSampler, p, 0);
  }
}
