#version 330
#extension GL_ARB_separate_shader_objects : require
#include <flame:step.glsl>
uniform sampler2D PreviousSampler;
uniform sampler2D VelocitySampler;
layout(location = 0) out vec4 fragColor;
float interpolateGas(vec3 position, int kind) {
  vec3 p = position / CELL_SIZE - .5;
  ivec3 a = ivec3(floor(p));
  vec3 f = fract(p);
  float sum = 0, weights = 0;
  for (int z = 0; z < 2; z++)
    for (int y = 0; y < 2; y++)
      for (int x = 0; x < 2; x++) {
        ivec3 q = a + ivec3(x, y, z);
        if (solidAt(q))
          continue;
        vec3 w = mix(1.0 - f, f, vec3(x, y, z));
        float weight = w.x * w.y * w.z;
        sum += gasAt(PreviousSampler, q, kind) * weight;
        weights += weight;
      }
  return weights > 1e-5 ? sum / weights : ambientGas(kind);
}
void main() {
  int i = fragmentIndex(), kind = i / CELLS;
  ivec3 p = gridCell(i % CELLS);
  if (solidAt(p) || kind == 4) {
    fragColor = encodeFloat(ambientGas(kind));
    return;
  }
  vec3 position = (vec3(p) + .5) * CELL_SIZE, back = position;
  vec3 motion = centeredVelocity(VelocitySampler, p) * DT;
  for (int j = 1; j <= 4; j++) {
    vec3 candidate = position - motion * float(j) / 4.0;
    if (solidAt(ivec3(floor(candidate / CELL_SIZE))))
      break;
    back = candidate;
  }
  float value = interpolateGas(back, kind),
        coefficient = (kind == 0   ? .22
                       : kind == 3 ? .25
                                   : .06),
        denominator = 1;
  for (int a = 0; a < 3; a++)
    for (int s = -1; s <= 1; s += 2) {
      ivec3 q = p + axisVector(a) * s;
      if (!solidAt(q)) {
        value += DT * coefficient * gasAt(PreviousSampler, q, kind);
        denominator += DT * coefficient;
      }
    }
  fragColor = encodeFloat(value / denominator);
}
