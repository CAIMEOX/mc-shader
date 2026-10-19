#version 330
#extension GL_ARB_separate_shader_objects : require
#include <manifold:render_data.glsl>
#include <manifold:gravity_settings.glsl>
#include <manifold:surface_finish.glsl>
#include <manifold:joinery_scene.glsl>
#include <manifold:joinery_illumination.glsl>
layout(location = 0) out vec4 fragColor;
void main() {
  fragColor = vec4(1, 1, 1, 1);
  if (FrameReady < .5 || Level < .5 || Level > 1.5)
    return;
  vec3 direction = worldRay(texCoord), normal;
  float travel;
  if (!joineryTrace(RayOrigin, direction, 650.0, travel, normal))
    return;
  vec2 light = joineryIllumination(RayOrigin + direction * travel, normal);
  fragColor = vec4(light, joineryEncodeDepth(travel));
}
