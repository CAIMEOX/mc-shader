#version 330
#extension GL_ARB_separate_shader_objects : require
#include <flame:packet.glsl>
uniform sampler2D MainSampler;
uniform sampler2D PreviousSampler;
layout(location = 0) out vec4 fragColor;
void main() {
  ivec2 p = ivec2(gl_FragCoord.xy), size = textureSize(MainSampler, 0);
  bool present = rgbWord(texelFetch(MainSampler, ivec2(0, size.y - 1), 0).rgb) == MAGIC;
  fragColor = present ? texelFetch(MainSampler, ivec2(p.x, size.y - 1 - p.y), 0)
                      : texelFetch(PreviousSampler, p, 0);
  fragColor.a = present ? 1.0 : 0.0;
}
