#version 330
#extension GL_ARB_separate_shader_objects : require
uniform sampler2D ControlSampler;
#include <qwen:codec.glsl>
void main() {
  uint phase = integer(ControlSampler, 0);
  vec2 p = vec2((gl_VertexIndex << 1) & 2, gl_VertexIndex & 2);
  gl_Position = phase == 1u || phase == 4u ? vec4(p * 2. - 1., 0, 1) : vec4(2, 2, 2, 1);
}
