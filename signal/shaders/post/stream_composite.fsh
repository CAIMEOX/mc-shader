#version 330
#extension GL_ARB_separate_shader_objects : require
#include <signal:codec.glsl>
#include <signal:stream_settings.glsl>
uniform sampler2D MainSampler;
uniform sampler2D StateSampler;
uniform sampler2D WorkSampler;
layout(location = 0) out vec4 fragColor;
void main() {
  ivec2 p = ivec2(gl_FragCoord.xy), size = textureSize(MainSampler, 0);
  fragColor =
      texelFetch(MainSampler, p.y == size.y - 1 && p.x < 2 ? ivec2(2, p.y) : p, 0);
  uint meta = decodeUint(texelFetch(StateSampler, ivec2(1, 0), 0));
  if (p.x >= 16 && p.x < 272 && p.y >= 16 && p.y < 80) {
    vec2 uv = (vec2(p) - vec2(16)) / vec2(256, 64);
    vec3 ink = mix(vec3(.1, .8, .6), vec3(1.0, .3, .1), float(meta & 63u) / 63.0);
    if (uv.y < .12 &&
        uv.x < clamp((float(meta >> 6u) - float(STREAM_WARMUP)) / float(STREAM_BITS),
                     0.0, 1.0))
      ink = vec3(1.0);
    fragColor = vec4(ink * (.6 + .4 * texture(WorkSampler, uv).rgb), 1.0);
  }
}
