#version 330
#extension GL_ARB_separate_shader_objects : require
#include <signal:codec.glsl>
#include <signal:stream_settings.glsl>
uniform sampler2D MainSampler;
uniform sampler2D PreviousSampler;
layout(location = 0) out vec4 fragColor;
void main() {
  uint previous = decodeUint(texelFetch(PreviousSampler, ivec2(0), 0));
  uint meta = decodeUint(texelFetch(PreviousSampler, ivec2(1, 0), 0));
  uint word = previous;
  int y = textureSize(MainSampler, 0).y - 1;
  if (rgbWord(texelFetch(MainSampler, ivec2(0, y), 0).rgb) == 0x534947u)
    word = rgbWord(texelFetch(MainSampler, ivec2(1, y), 0).rgb);
  uint frame = word != previous ? 0u : min((meta >> 6u) + 1u, 255u);
  uint low = word & 63u, high = (word >> 6u) & 63u;
  uint pattern = (word >> 12u) & 3u;
  bool stream = ((word >> 14u) & 1u) != 0u;
  uint power = low;
  if (!stream)
    frame = 0u;
  else if (frame == STREAM_WARMUP || frame == STREAM_WARMUP + STREAM_BITS + 1u)
    power = 63u;
  else if (frame > STREAM_WARMUP && frame <= STREAM_WARMUP + STREAM_BITS) {
    uint index = frame - STREAM_WARMUP - 1u;
    uint bit = pattern == 0u   ? 0u
               : pattern == 1u ? 1u
               : pattern == 2u ? index & 1u
                               : digest(STREAM_SEED + index) & 1u;
    power = bit == 0u ? low : high;
  } else if (frame > STREAM_WARMUP + STREAM_BITS + 1u)
    power = 0u;
  fragColor = encodeUint(gl_FragCoord.x < 1.0 ? word : (frame << 6u) | power);
}
