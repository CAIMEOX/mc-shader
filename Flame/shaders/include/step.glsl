#ifndef FLAME_STEP
#define FLAME_STEP
#include <flame:grid.glsl>
uniform sampler2D ControlSampler;
uniform sampler2D SolidSampler;
layout(std140) uniform Parameters {
  vec4 Values;
};
uint controlWord(int i) {
  return decodeUint(texelFetch(ControlSampler, ivec2(i, 0), 0));
}
bool resetStep() {
  return controlWord(5) != 0u && Values.x < .5;
}
bool solidAt(ivec3 p) {
  if (p.y >= GRID.y && p.x >= 0 && p.x < GRID.x && p.z >= 0 && p.z < GRID.z)
    return false;
  return !inGrid(p) || texelFetch(SolidSampler, address(cellIndex(p)), 0).r > .5;
}
bool openFace(ivec3 p, int axis) {
  return inGrid(p) && !solidAt(p) && !solidAt(p + axisVector(axis));
}
int materialAt(ivec3 p) {
  return inGrid(p)
             ? int(round(texelFetch(SolidSampler, address(cellIndex(p)), 0).g * 255.0))
             : 0;
}
float exposureAt(ivec3 p) {
  return inGrid(p) ? round(texelFetch(SolidSampler, address(cellIndex(p)), 0).b * 255.0)
                   : 0.0;
}
float initialFuel(ivec3 p) {
  return solidAt(p) && exposureAt(p) > 0.0 ? FUEL_LOAD[materialAt(p)] : 0.0;
}
float stored(sampler2D field, ivec3 p, int kind) {
  return inGrid(p)
             ? decodeFloat(texelFetch(field, address(cellIndex(p) + kind * CELLS), 0))
             : 0.0;
}
float ambientGas(int kind) {
  return kind == 0 ? AMBIENT : kind == 3 ? 1.0 : 0.0;
}
float gasAt(sampler2D field, ivec3 p, int kind) {
  return !inGrid(p) || resetStep() ? ambientGas(kind) : stored(field, p, kind);
}
vec3 centeredVelocity(sampler2D field, ivec3 p) {
  if (resetStep())
    return vec3(0);
  return .5 * vec3(faceValue(field, p, 0) + faceValue(field, p - ivec3(1, 0, 0), 0),
                   faceValue(field, p, 1) + faceValue(field, p - ivec3(0, 1, 0), 1),
                   faceValue(field, p, 2) + faceValue(field, p - ivec3(0, 0, 1), 2));
}
#endif
