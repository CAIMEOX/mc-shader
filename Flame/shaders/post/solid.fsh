#version 330
#extension GL_ARB_separate_shader_objects : require
#include <flame:grid.glsl>
uniform sampler2D TerrainSampler;
layout(location = 0) out vec4 fragColor;
ivec2 terrain(ivec3 cell) {
  ivec3 p = cell / 2;
  int i = p.x + REGION.x * (p.y + REGION.y * p.z);
  return ivec2(round(texelFetch(TerrainSampler, ivec2(i % 16, i / 16), 0).rg * 255.0));
}
bool occupied(ivec3 p) {
  if (!inGrid(p))
    return p.y < GRID.y;
  int shape = terrain(p).x, mask = shape < 28 ? SHAPE_MASKS[shape] : 255,
      octant = p.x % 2 + 2 * (p.y % 2) + 4 * (p.z % 2);
  return ((mask >> octant) & 1) != 0;
}
void main() {
  ivec3 p = gridCell(fragmentIndex());
  bool solid = occupied(p);
  int exposed = 0;
  if (solid)
    for (int a = 0; a < 3; a++)
      for (int s = -1; s <= 1; s += 2)
        if (!occupied(p + axisVector(a) * s))
          exposed++;
  fragColor =
      vec4(solid ? 1.0 : 0.0, float(terrain(p).y) / 255.0, float(exposed) / 255.0, 1);
}
