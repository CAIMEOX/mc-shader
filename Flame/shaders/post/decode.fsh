#version 330
#extension GL_ARB_separate_shader_objects : require
#include <flame:packet.glsl>
uniform sampler2D PacketSampler;
layout(location = 0) out vec4 fragColor;
void main() {
  ivec2 p = ivec2(gl_FragCoord.xy);
  int index = p.x + 16 * p.y;
  uint value = packetBits(PacketSampler, 5 + HEADER_WORDS, index * 7, 7);
  fragColor = vec4(float(value & 31u) / 255.0, float(value >> 5u) / 255.0, 0, 1);
}
