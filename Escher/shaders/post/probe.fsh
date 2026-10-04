#version 330
#extension GL_ARB_separate_shader_objects : require
#include <escher:render_data.glsl>
#include <escher:space.glsl>
#include <escher:distance.glsl>
#include <escher:folding_settings.glsl>
#include <escher:folding_scene.glsl>
layout(location = 0) out vec4 fragColor;
void main() {
  int i = int(gl_FragCoord.x);
  if (i >= 16) {
    int column = (i - 16) / 4, position = (i - 16) % 4;
    const float offsets[4] = float[](-.08, -.0001, .0001, .08);
    float x =
        -FOLD_WIDTH * .5 + (float(column) + .5) * FOLD_WIDTH / 16. + offsets[position];
    fragColor = encodeFloat(foldingScene(vec3(x, 1.3, 7.4 * FOLD_WIDTH / 128.)).x);
    return;
  }
  vec3 camera = embed(RayOrigin);
  float value = i < 3     ? RayOrigin[i]
                : i < 6   ? camera[i - 3]
                : i < 10  ? Lens[i - 6]
                : i == 10 ? FrameReady
                : i == 11 ? RenderQuality
                          : FoldingData[i - 12];
  fragColor = encodeFloat(value);
}
