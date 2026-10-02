#version 330
#extension GL_ARB_separate_shader_objects : require
#include <flame:render_data.glsl>
uniform sampler2D DepthSampler;
layout(location = 0) out vec4 fragColor;
void main() {
  fragColor = encodeFloat(sceneDistance(DepthSampler, texCoord));
}
