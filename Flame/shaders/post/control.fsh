#version 330
#extension GL_ARB_separate_shader_objects : require
#include <minecraft:globals.glsl>
#include <flame:packet.glsl>
uniform sampler2D PacketSampler;
uniform sampler2D PreviousSampler;
layout(location = 0) out vec4 fragColor;
float previousFloat(int i) {
  return decodeFloat(texelFetch(PreviousSampler, ivec2(i, 0), 0));
}
uint previousUint(int i) {
  return decodeUint(texelFetch(PreviousSampler, ivec2(i, 0), 0));
}
void main() {
  int index = int(gl_FragCoord.x);
  float now = GameTime * 1200.0;
  bool valid = validPacket(PacketSampler);
  uint epoch = packetWord(PacketSampler, 5);
  bool restart = valid && epoch != previousUint(0);
  float elapsed = min(.1, mod(now - previousFloat(1), 1200.0));
  float accumulator = restart ? DT : min(.1, previousFloat(2) + elapsed);
  uint steps = valid ? uint(clamp(floor((accumulator + 1e-5) / DT), 0.0, 2.0)) : 0u;
  accumulator -= float(steps) * DT;
  if (index == 0)
    fragColor = encodeUint(valid ? epoch : previousUint(0));
  else if (index == 1)
    fragColor = encodeFloat(now);
  else if (index == 2)
    fragColor = encodeFloat(valid ? accumulator : 0.0);
  else if (index == 3)
    fragColor = encodeUint(steps);
  else if (index == 4)
    fragColor = encodeUint((restart ? 0u : previousUint(4)) + steps);
  else if (index == 5)
    fragColor = encodeUint(restart ? 1u : 0u);
  else if (index == 6)
    fragColor = encodeUint(valid ? 1u : 0u);
  else
    fragColor = encodeUint(valid && sourceEnabled(PacketSampler) ? 1u : 0u);
}
