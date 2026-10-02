#version 330
#extension GL_ARB_separate_shader_objects : require
#include <flame:step.glsl>
uniform sampler2D PreviousSampler;
uniform sampler2D GasSampler;
uniform sampler2D CurlSampler;
layout(location = 0) out vec4 fragColor;
float curlMagnitude(ivec3 p) {
  return inGrid(p) ? texelFetch(CurlSampler, address(cellIndex(p)), 0).a * 30.0 : 0.0;
}
vec3 confinement(ivec3 p) {
  vec3 gradient =
      vec3(curlMagnitude(p + ivec3(1, 0, 0)) - curlMagnitude(p - ivec3(1, 0, 0)),
           curlMagnitude(p + ivec3(0, 1, 0)) - curlMagnitude(p - ivec3(0, 1, 0)),
           curlMagnitude(p + ivec3(0, 0, 1)) - curlMagnitude(p - ivec3(0, 0, 1)));
  vec3 w = (texelFetch(CurlSampler, address(cellIndex(clamp(p, ivec3(0), GRID - 1))), 0)
                    .rgb *
                2.0 -
            1.0) *
           30.0;
  return .45 * CELL_SIZE * cross(gradient / (length(gradient) + 1e-4), w);
}
float interpolateFace(vec3 position, int axis) {
  vec3 p = position / CELL_SIZE - .5 - vec3(axisVector(axis)) * .5;
  ivec3 a = ivec3(floor(p));
  vec3 f = fract(p);
  float result = 0;
  for (int z = 0; z < 2; z++)
    for (int y = 0; y < 2; y++)
      for (int x = 0; x < 2; x++) {
        vec3 w = mix(1.0 - f, f, vec3(x, y, z));
        result += faceValue(PreviousSampler,
                            clamp(a + ivec3(x, y, z), ivec3(0), GRID - 1), axis) *
                  w.x * w.y * w.z;
      }
  return result;
}
void main() {
  int i = fragmentIndex(), axis = i / CELLS;
  ivec3 p = gridCell(i % CELLS), e = axisVector(axis);
  float velocity = 0;
  if (openFace(p, axis)) {
    if (!resetStep()) {
      vec3 flow = .5 * (centeredVelocity(PreviousSampler, p) +
                        centeredVelocity(PreviousSampler, p + e));
      vec3 position = (vec3(p) + .5 + .5 * vec3(e)) * CELL_SIZE,
           back = position - DT * flow;
      velocity = solidAt(ivec3(floor(back / CELL_SIZE)))
                     ? faceValue(PreviousSampler, p, axis)
                     : interpolateFace(back, axis);
    }
    float heat = .5 * (gasAt(GasSampler, p, 0) + gasAt(GasSampler, p + e, 0)) - AMBIENT;
    float smoke = .5 * (gasAt(GasSampler, p, 2) + gasAt(GasSampler, p + e, 2));
    vec3 force = .5 * (confinement(p) + confinement(p + e));
    force.y += .014 * heat - .6 * smoke;
    velocity = clamp((velocity + DT * force[axis]) * exp(-.12 * DT), -8.0, 8.0);
  }
  fragColor = encodeFloat(velocity);
}
