#version 330
#extension GL_ARB_separate_shader_objects : require
#include <signal:codec.glsl>
uniform sampler2D MainSampler;
uniform sampler2D StateSampler;
uniform sampler2D WorkSampler;
layout(location = 0) out vec4 fragColor;
void main() {
  ivec2 p = ivec2(gl_FragCoord.xy), size = textureSize(MainSampler, 0);
  fragColor =
      texelFetch(MainSampler, p.y == size.y - 1 && p.x < 2 ? ivec2(2, p.y) : p, 0);
  uint word = decodeUint(texelFetch(StateSampler, ivec2(0), 0));
  uint hash = decodeUint(texelFetch(StateSampler, ivec2(1, 0), 0));
  if (p.x >= 16 && p.x < 272 && p.y >= 16 && p.y < 80) {
    vec2 uv = (vec2(p) - vec2(16)) / vec2(256, 64);
    uint symbol = resultSymbol(word, hash);
    vec3 ink = symbol == 0u   ? vec3(.10, .80, .60)
               : symbol == 1u ? vec3(1.0, .42, .10)
               : symbol == 2u ? vec3(.70, .25, .95)
                              : vec3(.20, .60, 1.0);
    fragColor = vec4(ink * (.6 + .4 * texture(WorkSampler, uv).rgb), 1.0);
  }
}
