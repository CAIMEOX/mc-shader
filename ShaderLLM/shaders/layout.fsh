#version 330
#extension GL_ARB_separate_shader_objects : require
uniform sampler2D OutputSampler, ResultSampler;
layout(location = 0) out vec4 fragColor;
#include <qwen:codec.glsl>
#include <qwen:text.glsl>
void main() {
  int count = int(integer(ResultSampler, 8)), pos = 0, x = 0, y = 0;
  while (pos < count) {
    int c = nextCodepoint(OutputSampler, pos, count);
    if (c < 0)
      break;
    if (c == 10) {
      x = 0;
      y++;
    } else if (++x == 32) {
      x = 0;
      y++;
    }
  }
  fragColor = packU(uint(max(0, y - 8)));
}
