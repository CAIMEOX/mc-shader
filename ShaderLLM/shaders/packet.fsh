#version 330
#extension GL_ARB_separate_shader_objects : require
uniform sampler2D MainSampler;
layout(location = 0) out vec4 fragColor;
#include <qwen:codec.glsl>
void main() {
  ivec2 cell = ivec2(gl_FragCoord.xy), size = textureSize(MainSampler, 0);
  ivec4 c = ivec4(round(
      texelFetch(MainSampler, ivec2(cell.x * 2, size.y - 1 - cell.y * 2), 0) * 255.));
  int i = cell.x + cell.y * 32;
  uint value = 0u;
  if (i < 3) {
    int kind = i == 0 ? 237 : (i == 1 ? 236 : 235);
    value = c.b == kind ? uint((c.r << 8) | c.g) : 0xffffffffu;
  } else
    value = c.b == 239 ? uint((c.r << 8) | c.g) : 0xffffffffu;
  fragColor = packU(value);
}
