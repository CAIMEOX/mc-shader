#version 330
#extension GL_ARB_separate_shader_objects : require
#include <signal:codec.glsl>
#include <signal:message.glsl>
uniform sampler2D MainSampler;
uniform sampler2D PreviousSampler;
layout(location = 0) out vec4 fragColor;
void main() {
  int y = textureSize(MainSampler, 0).y - 1;
  if (rgbWord(texelFetch(MainSampler, ivec2(0, y), 0).rgb) != 0x534947u) {
    fragColor = texelFetch(PreviousSampler, ivec2(gl_FragCoord.xy), 0);
    return;
  }
  uint word = rgbWord(texelFetch(MainSampler, ivec2(1, y), 0).rgb);
  uint bitIndex = (word & 65535u) - 1u;
  fragColor = encodeUint(gl_FragCoord.x < 1.0 ? word : messageBit(bitIndex));
}
