
#include <minecraft:globals.glsl>
#include <signal:codec.glsl>
uniform sampler2D Sampler0;
layout(location = 10) flat out int SignalCarrier;
layout(location = 11) flat out vec3 SignalWord;
void main() {
  vec4 marker = texelFetch(Sampler0, ivec2(UV0 * vec2(textureSize(Sampler0, 0))), 0);
  int index = int(round(marker.r * 255.0));
  SignalCarrier =
      int(abs(marker.b * 255.0 - 239.0) < .1 && abs(marker.a * 255.0 - 247.0) < .1 &&
          marker.g == 0.0 && index < 2);
  SignalWord = index == 0 ? wordRgb(0x534947u) : Color.rgb;
  if (SignalCarrier != 0) {
    const vec2 corners[4] = vec2[](vec2(0, 1), vec2(0, 0), vec2(1, 0), vec2(1, 1));
    vec2 pixel = vec2(index, int(ScreenSize.y) - 1);
    gl_Position =
        vec4((pixel + corners[gl_VertexIndex % 4]) * 2.0 / ScreenSize - 1.0, 1.0, 1.0);
    return;
  }
