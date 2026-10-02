#version 330
#extension GL_ARB_separate_shader_objects : require
uniform sampler2D ControlSampler, TokensSampler, ChoiceSampler, TokenMetaSampler,
    TokenBytesSampler;
layout(location = 0) out vec4 fragColor;
#include <qwen:codec.glsl>
#include <qwen:limits.glsl>
#include <qwen:model.glsl>
void main() {
  uint c[12];
  for (int j = 0; j < 12; j++)
    c[j] = integer(ControlSampler, j);
  uint phase = c[0];
  c[10]++;
  if (phase == 1u) {
    c[5] = integer(TokensSampler, 0);
    c[0] = integer(TokensSampler, 1) == 0u && c[5] > 0u ? 2u : 7u;
    c[4] = integer(TokensSampler, 2);
  } else if (phase == 2u) {
    c[0] = 3u;
    c[3] = 0u;
  } else if (phase == 3u) {
    c[3] += uint(LAYERS_PER_FRAME);
    if (c[3] >= uint(LAYER_COUNT)) {
      if (c[2] + 1u < c[5]) {
        c[2]++;
        c[4] = integer(TokensSampler, 2 + int(c[2]));
        c[0] = 2u;
      } else {
        c[0] = 4u;
        c[7] = 0u;
      }
    }
  } else if (phase == 4u) {
    uint id = integer(ChoiceSampler, 1);
    c[6]++;
    c[4] = id;
    uint added = id != 151643u && id != 151645u
                     ? integer(TokenMetaSampler, int(id) * 2 + 1)
                     : 0u;
    if (c[8] + added > uint(OUTPUT_BYTES)) {
      c[0] = 7u;
      c[11] = 5u;
      fragColor = packU(c[int(gl_FragCoord.x)]);
      return;
    }
    c[8] += added;
    if (id == 151643u || id == 151645u || c[6] >= c[9] ||
        c[2] + 1u >= uint(CONTEXT_SIZE))
      c[0] = 6u;
    else {
      c[2]++;
      c[0] = 2u;
    }
  }
  fragColor = packU(c[int(gl_FragCoord.x)]);
}
