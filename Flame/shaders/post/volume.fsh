#version 330
#extension GL_ARB_separate_shader_objects : require
#include <flame:volume.glsl>
uniform sampler2D DepthSampler;
layout(location = 0) out vec4 fragColor;
void main() {
  fragColor = FrameReady > .5
                  ? traceVolume(texCoord, sceneDistance(DepthSampler, texCoord), true)
                  : vec4(0);
}
