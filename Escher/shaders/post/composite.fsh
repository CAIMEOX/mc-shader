#version 330
#include <escher:packet.glsl>
uniform sampler2D MainSampler;
uniform sampler2D Gallery0Sampler;
uniform sampler2D Gallery1Sampler;
uniform sampler2D Gallery2Sampler;
uniform sampler2D Gallery3Sampler;
uniform sampler2D PacketSampler;
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
  if (validPacket(PacketSampler)) {
    vec2 uv = (vec2(p) + .5) / vec2(size);
    uint quality = bits(PacketSampler, FIELD_QUALITY, 2);
    if (quality == 0u)
      fragColor = reconstruct(Gallery0Sampler, uv);
    else if (quality == 1u)
      fragColor = reconstruct(Gallery1Sampler, uv);
    else if (quality == 2u)
      fragColor = reconstruct(Gallery2Sampler, uv);
    else
      fragColor = reconstruct(Gallery3Sampler, uv);
  } else {
    if (p.y == size.y - 1 && p.x < PACKET_SIZE.x)
      p.y--;
    fragColor = texelFetch(MainSampler, p, 0);
  }
}
