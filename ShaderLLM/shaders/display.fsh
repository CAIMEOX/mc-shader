#version 330
#extension GL_ARB_separate_shader_objects : require
uniform sampler2D MainSampler, GridSampler, ControlSampler, GlyphsSampler;
layout(location = 0) out vec4 fragColor;
#include <qwen:codec.glsl>
#include <qwen:limits.glsl>
#include <qwen:model.glsl>
void main() {
  ivec2 pixel = ivec2(gl_FragCoord.xy), size = textureSize(MainSampler, 0);
  fragColor = texelFetch(MainSampler, pixel, 0);
  // Restore the small transport strip from the neighboring row.
  if (pixel.x < 64 && pixel.y >= size.y - 10)
    fragColor = texelFetch(MainSampler, ivec2(pixel.x, size.y - 11), 0);
  ivec2 physical = ivec2(pixel.x - 24, size.y - 48 - pixel.y);
  if (physical.x < 0 || physical.y < 0)
    return;
  ivec2 local = physical / 2;
  if (local.x < 0 || local.y < 0 || local.x >= 512 || local.y >= 160)
    return;
  fragColor = mix(fragColor, vec4(.035, .045, .065, 1), .92);
  int c =
      local.y < 144 ? int(integer(GridSampler, (local.y / 16) * 32 + local.x / 16)) : 0;
  if (c > 0 && c < 0x110000) {
    int row = local.y % 16, col = local.x % 16;
    uint bits = integer(GlyphsSampler, c * 8 + row / 2);
    bits = (row % 2 == 0 ? bits >> 16 : bits) & 65535u;
    if ((bits & (1u << uint(15 - col))) != 0u)
      fragColor = vec4(.84, .94, 1, 1);
  }
  // Progress strip: phase, layer, generated-token count.
  if (local.y >= 152) {
    float progress = integer(ControlSampler, 0) == 6u
                         ? 1.
                         : float(integer(ControlSampler, 3)) / float(LAYER_COUNT);
    if (float(local.x) < progress * 512.)
      fragColor = vec4(.22, .65, .9, 1);
  }
}
