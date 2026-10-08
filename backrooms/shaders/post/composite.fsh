#version 330
#include <backrooms:packet.glsl>
uniform sampler2D MainSampler;
uniform sampler2D SceneSampler;
uniform sampler2D PacketSampler;
layout(location = 0) out vec4 fragColor;
void main() {
  ivec2 p = ivec2(gl_FragCoord.xy), size = textureSize(MainSampler, 0);
  if (validPacket(PacketSampler)) {
    vec2 uv = (vec2(p) + .5) / vec2(size);
    vec3 c = texture(SceneSampler, uv).rgb;
    float vignette = 1.0 - .085 * dot(uv - .5, uv - .5);
    fragColor = vec4(c * vignette, 1);
  } else {
    if (p.y == size.y - 1 && p.x < PACKET_WORDS)
      p.y--;
    fragColor = texelFetch(MainSampler, p, 0);
  }
}
