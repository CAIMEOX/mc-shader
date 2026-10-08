#version 330
uniform sampler2D InSampler;
layout(location = 0) out vec4 fragColor;
void main() {
  fragColor = texelFetch(InSampler, ivec2(gl_FragCoord.xy), 0);
}
