#version 330
#extension GL_ARB_separate_shader_objects : require
uniform sampler2D ControlSampler, PreviousSampler, ChoiceSampler, TokenMetaSampler,
    TokenBytesSampler;
layout(location = 0) out vec4 fragColor;
#include <qwen:codec.glsl>
#include <qwen:limits.glsl>
void main() {
  int i = int(gl_FragCoord.x);
  uint phase = integer(ControlSampler, 0);
  if (phase == 1u) {
    fragColor = packU(0u);
    return;
  }
  if (phase == 4u) {
    uint id = integer(ChoiceSampler, 1);
    int offset = int(integer(ControlSampler, 8));
    int start = int(integer(TokenMetaSampler, int(id) * 2)),
        length = int(integer(TokenMetaSampler, int(id) * 2 + 1));
    if (offset + length <= OUTPUT_BYTES && id != 151643u && id != 151645u &&
        i >= offset && i < offset + length) {
      int byteIndex = start + i - offset;
      uvec4 v = uvec4(round(at(TokenBytesSampler, byteIndex / 4) * 255.));
      fragColor = packU(v[byteIndex % 4]);
      return;
    }
  }
  fragColor = at(PreviousSampler, i);
}
