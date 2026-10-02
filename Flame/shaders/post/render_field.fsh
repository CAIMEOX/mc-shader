#version 330
#extension GL_ARB_separate_shader_objects : require
#include <flame:grid.glsl>
uniform sampler2D GasSampler;
uniform sampler2D SolidSampler;
layout(location = 0) out vec4 fragColor;
float field(int i, int kind) {
  return decodeFloat(texelFetch(GasSampler, address(i + kind * CELLS), 0));
}
void main() {
  int i = fragmentIndex();
  if (texelFetch(SolidSampler, address(i), 0).r > .5) {
    fragColor = vec4(0);
    return;
  }
  fragColor = clamp(vec4((field(i, 0) - AMBIENT) / 2000.0, field(i, 2) / 2.0,
                         field(i, 4) / .30, field(i, 1) * 10.0),
                    0.0, 1.0);
}
