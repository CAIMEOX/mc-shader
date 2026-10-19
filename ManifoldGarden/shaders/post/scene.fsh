#version 330
#extension GL_ARB_separate_shader_objects : require
#include <minecraft:globals.glsl>
#include <manifold:render_data.glsl>
#include <manifold:gravity_render.glsl>
layout(location = 0) out vec4 fragColor;
layout(std140) uniform Parameters {
  vec4 Values;
};
void main() {
  if (FrameReady < .5 || abs(RenderQuality - Values.x) > .5) {
    fragColor = vec4(0);
    return;
  }
  fragColor = renderGravity(Values.w > 0.0 ? Values.w : ScreenSize.y, int(Values.y));
}
