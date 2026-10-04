#version 330
#include <escher:packet.glsl>
uniform sampler2D MainSampler;
layout(location = 0) out vec4 fragColor;
void main() {
  ivec2 size = textureSize(MainSampler, 0), p = ivec2(gl_FragCoord.xy);
  bool present = rgbWord(texelFetch(MainSampler, ivec2(0, size.y - 1), 0).rgb) == MAGIC;
  fragColor = present ? texelFetch(MainSampler, ivec2(p.x, size.y - 1), 0) : vec4(0);
}
