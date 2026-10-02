#version 330
#extension GL_ARB_separate_shader_objects : require
#include <flame:step.glsl>
uniform sampler2D VelocitySampler;
layout(location = 0) out vec4 fragColor;
void main() {
  ivec3 p = gridCell(fragmentIndex());
  float d = 0;
  if (!solidAt(p))
    for (int a = 0; a < 3; a++)
      d += (faceValue(VelocitySampler, p, a) -
            faceValue(VelocitySampler, p - axisVector(a), a)) /
           CELL_SIZE;
  fragColor = encodeFloat(d);
}
