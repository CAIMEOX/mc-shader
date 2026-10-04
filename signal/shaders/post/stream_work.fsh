#version 330
#extension GL_ARB_separate_shader_objects : require
#include <signal:codec.glsl>
#include <signal:stream_settings.glsl>
uniform sampler2D StateSampler;
layout(location = 0) out vec4 fragColor;
void main() {
  uint meta = decodeUint(texelFetch(StateSampler, ivec2(1, 0), 0));
  int iterations = int(meta & 63u) * ITERATIONS_PER_POWER;
  vec4 v = fract(vec4(gl_FragCoord.xy * .017, float(meta >> 6u) * .0001, .613));
  for (int i = 0; i < iterations; i++)
    v = fract(sin(v.wxyz * vec4(3.13, 2.71, 4.17, 1.61) + v.zwxy) * 17.137 + .123);
  fragColor = vec4(v.rgb, 1.0);
}
