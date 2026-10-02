#version 330
#extension GL_ARB_separate_shader_objects : require
#include <flame:step.glsl>
uniform sampler2D PreviousSampler;
uniform sampler2D PressureSampler;
layout(location = 0) out vec4 fragColor;
void main() {
  int i = fragmentIndex(), a = i / CELLS;
  ivec3 p = gridCell(i % CELLS), q = p + axisVector(a);
  float v = 0;
  if (openFace(p, a))
    v = faceValue(PreviousSampler, p, a) -
        (cellValue(PressureSampler, q) - cellValue(PressureSampler, p)) * DT /
            CELL_SIZE;
  fragColor = encodeFloat(clamp(v, -8.0, 8.0));
}
