#version 330
#extension GL_ARB_separate_shader_objects : require
uniform sampler2D InSampler;
layout(location = 0) out vec4 fragColor;
void main() {
  fragColor = texelFetch(InSampler, ivec2(gl_FragCoord.xy), 0);
}
