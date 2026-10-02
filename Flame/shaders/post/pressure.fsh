#version 330
#extension GL_ARB_separate_shader_objects : require
#include <flame:step.glsl>
uniform sampler2D PreviousSampler;
uniform sampler2D RhsSampler;
layout(location = 0) out vec4 fragColor;
void main() {
  ivec3 p = gridCell(fragmentIndex());
  float sum = 0, diagonal = 0;
  if (!solidAt(p)) {
    for (int a = 0; a < 3; a++)
      for (int s = -1; s <= 1; s += 2) {
        ivec3 q = p + axisVector(a) * s;
        if (!solidAt(q)) {
          diagonal += 1.0;
          sum += cellValue(PreviousSampler, q);
        }
      }
    if (diagonal > 0.0)
      sum = mix(
          cellValue(PreviousSampler, p),
          (sum - cellValue(RhsSampler, p) * CELL_SIZE * CELL_SIZE / DT) / diagonal, .8);
    else
      sum = 0.0;
  }
  fragColor = encodeFloat(sum);
}
