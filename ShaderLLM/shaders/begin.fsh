#version 330
#extension GL_ARB_separate_shader_objects : require
uniform sampler2D ControlSampler, PacketSampler;
layout(location = 0) out vec4 fragColor;
#include <qwen:codec.glsl>
#include <qwen:limits.glsl>
void main() {
  int i = int(gl_FragCoord.x);
  uint epoch = integer(PacketSampler, 0), length = integer(PacketSampler, 1);
  bool valid = epoch != 0xffffffffu && length <= 128u;
  for (uint j = 0u; j < length && valid; j++)
    if (integer(PacketSampler, 3 + int(j)) == 0xffffffffu)
      valid = false;
  if (valid && epoch != integer(ControlSampler, 1))
    fragColor = packU(i == 0 ? 1u
                             : (i == 1 ? epoch
                                       : (i == 9 ? clamp(integer(PacketSampler, 2), 1u,
                                                         uint(MAX_GENERATION))
                                                 : 0u)));
  else
    fragColor = at(ControlSampler, i);
}
