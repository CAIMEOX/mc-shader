#version 330
#extension GL_ARB_separate_shader_objects : require
uniform sampler2D ControlSampler, PreviousSampler, ChoiceSampler;
layout(location = 0) out vec4 fragColor;
#include <qwen:codec.glsl>
void main() {
  int i = int(gl_FragCoord.x);
  uint phase = integer(ControlSampler, 0);
  fragColor = phase == 1u ? packU(0u)
                          : (phase == 4u && i == int(integer(ControlSampler, 6))
                                 ? at(ChoiceSampler, 1)
                                 : at(PreviousSampler, i));
}
