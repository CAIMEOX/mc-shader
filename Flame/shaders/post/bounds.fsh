#version 330
#extension GL_ARB_separate_shader_objects : require
#include <flame:grid.glsl>
uniform sampler2D FieldSampler;
layout(location = 0) out vec4 fragColor;
void main() {
  ivec2 pixel = ivec2(gl_FragCoord.xy);
  int i = pixel.x + 16 * pixel.y;
  ivec3 base =
      ivec3(i % COARSE.x, (i / COARSE.x) % COARSE.y, i / (COARSE.x * COARSE.y)) * 4;
  float peak = 0;
  for (int z = -1; z <= 4; z++)
    for (int y = -1; y <= 4; y++)
      for (int x = -1; x <= 4; x++) {
        ivec3 p = base + ivec3(x, y, z);
        if (inGrid(p)) {
          vec4 v = texelFetch(FieldSampler, address(cellIndex(p)), 0);
          peak = max(peak, max(v.g, v.b));
        }
      }
  fragColor = vec4(peak, 0, 0, 1);
}
