#version 330
#extension GL_ARB_separate_shader_objects : require
uniform sampler2D OutputSampler, ResultSampler, LayoutSampler;
layout(location = 0) out vec4 fragColor;
#include <qwen:codec.glsl>
#include <qwen:text.glsl>
void main() {
  ivec2 target = ivec2(gl_FragCoord.xy);
  target.y += int(integer(LayoutSampler, 0));
  int count = int(integer(ResultSampler, 8)), pos = 0, x = 0, y = 0, code = 0;
  while (pos < count) {
    int c = nextCodepoint(OutputSampler, pos, count);
    if (c < 0)
      break;
    if (c == 10) {
      x = 0;
      y++;
      continue;
    }
    if (x == target.x && y == target.y) {
      code = c;
      break;
    }
    if (++x == 32) {
      x = 0;
      y++;
    }
    if (y > target.y)
      break;
  }
  fragColor = packU(uint(code));
}
