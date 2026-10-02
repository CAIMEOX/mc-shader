#ifndef FLAME_GRID
#define FLAME_GRID
#include <flame:settings.glsl>
#include <flame:codec.glsl>
bool inGrid(ivec3 p) {
  return all(greaterThanEqual(p, ivec3(0))) && all(lessThan(p, GRID));
}
int cellIndex(ivec3 p) {
  return p.x + GRID.x * (p.y + GRID.y * p.z);
}
ivec3 gridCell(int i) {
  return ivec3(i % GRID.x, (i / GRID.x) % GRID.y, i / (GRID.x * GRID.y));
}
ivec2 address(int i) {
  return ivec2(i % 256, i / 256);
}
#ifndef FLAME_RENDER_VERTEX
int fragmentIndex() {
  ivec2 p = ivec2(gl_FragCoord.xy);
  return p.x + 256 * p.y;
}
#endif
ivec3 axisVector(int axis) {
  return axis == 0 ? ivec3(1, 0, 0) : axis == 1 ? ivec3(0, 1, 0) : ivec3(0, 0, 1);
}
float cellValue(sampler2D source, ivec3 p) {
  return inGrid(p) ? decodeFloat(texelFetch(source, address(cellIndex(p)), 0)) : 0.0;
}
float faceValue(sampler2D source, ivec3 p, int axis) {
  return inGrid(p)
             ? decodeFloat(texelFetch(source, address(cellIndex(p) + axis * CELLS), 0))
             : 0.0;
}
#endif
