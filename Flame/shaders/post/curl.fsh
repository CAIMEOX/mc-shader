#version 330
#extension GL_ARB_separate_shader_objects : require
#include <flame:step.glsl>
uniform sampler2D VelocitySampler;
layout(location = 0) out vec4 fragColor;
void main() {
  ivec3 p = gridCell(fragmentIndex());
  vec3 dx = (centeredVelocity(VelocitySampler, p + ivec3(1, 0, 0)) -
             centeredVelocity(VelocitySampler, p - ivec3(1, 0, 0))) /
            (2.0 * CELL_SIZE);
  vec3 dy = (centeredVelocity(VelocitySampler, p + ivec3(0, 1, 0)) -
             centeredVelocity(VelocitySampler, p - ivec3(0, 1, 0))) /
            (2.0 * CELL_SIZE);
  vec3 dz = (centeredVelocity(VelocitySampler, p + ivec3(0, 0, 1)) -
             centeredVelocity(VelocitySampler, p - ivec3(0, 0, 1))) /
            (2.0 * CELL_SIZE);
  vec3 w = solidAt(p) ? vec3(0) : vec3(dy.z - dz.y, dz.x - dx.z, dx.y - dy.x);
  fragColor =
      vec4(clamp(w / 30.0, -1.0, 1.0) * .5 + .5, clamp(length(w) / 30.0, 0.0, 1.0));
}
