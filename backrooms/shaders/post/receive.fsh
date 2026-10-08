#version 330
#include <backrooms:packet.glsl>
uniform sampler2D MainSampler;
uniform sampler2D PreviousSampler;
layout(location = 0) out vec4 fragColor;
void main() {
  ivec2 size = textureSize(MainSampler, 0), p = ivec2(gl_FragCoord.xy);
  bool fresh = rgbWord(texelFetch(MainSampler, ivec2(0, size.y - 1), 0).rgb) == MAGIC;
  fragColor = fresh ? texelFetch(MainSampler, ivec2(p.x, size.y - 1), 0)
                    : texelFetch(PreviousSampler, p, 0);
  if (!fresh && p.x == 0)
    fragColor.a = max(0.0, fragColor.a - 1.0 / 32.0);
}
