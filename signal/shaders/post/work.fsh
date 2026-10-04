#version 330
#extension GL_ARB_separate_shader_objects : require
#include <signal:codec.glsl>
#include <signal:settings.glsl>
uniform sampler2D StateSampler;
layout(location = 0) out vec4 fragColor;
void main() {
  uint word = decodeUint(texelFetch(StateSampler, ivec2(0, 0), 0));
  uint hash = decodeUint(texelFetch(StateSampler, ivec2(1, 0), 0));
  uint symbol = resultSymbol(word, hash);
  int power = (word >> 16u & 3u) == 3u ? FOUR_POWERS[int(symbol ^ (symbol >> 1u))]
              : symbol == 1u           ? int((word >> 18u) & 63u)
                                       : 0;
  int iterations = power * ITERATIONS_PER_POWER;
  vec4 v = fract(vec4(gl_FragCoord.xy * .017, float(hash & 65535u) * .0001, .613));
  for (int i = 0; i < iterations; i++) {
    v = fract(sin(v.wxyz * vec4(3.13, 2.71, 4.17, 1.61) + v.zwxy) * 17.137 + .123);
  }
  fragColor = vec4(v.rgb, 1.0);
}
