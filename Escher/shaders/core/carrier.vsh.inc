
#include <minecraft:globals.glsl>
#include <escher:settings.glsl>
#include <escher:codec.glsl>
#include <escher:rotation.glsl>
uniform sampler2D Sampler0;
layout(location = 10) flat out int EscherCarrier;
layout(location = 11) flat out vec3 EscherWord;
void main() {
  vec4 marker = texelFetch(Sampler0, ivec2(UV0 * vec2(textureSize(Sampler0, 0))), 0);
  int index = int(round(marker.r * 255.0)) + 256 * int(round(marker.g * 255.0));
  EscherCarrier = int(abs(marker.b * 255.0 - 239.0) < .1 &&
                      abs(marker.a * 255.0 - 247.0) < .1 && index < PACKET_WORDS);
  EscherWord = Color.rgb;
  if (EscherCarrier != 0) {
    if (index == 0)
      EscherWord = wordRgb(MAGIC);
    if (index == 1 || index == 2) {
      mat3 basis = mat3(normalize(ModelViewMat[0].xyz), normalize(ModelViewMat[1].xyz),
                        normalize(ModelViewMat[2].xyz));
      uvec2 rotation = encodeRotation(basisQuaternion(basis));
      EscherWord = wordRgb(index == 1 ? rotation.x : rotation.y);
    }
    if (index == 3)
      EscherWord = wordRgb(encodeFloat24(ProjMat[1][1]));
    if (index == 4) {
      float bias = 0.0;
#ifndef RENDERPEARL_DEPTH_IS_ZERO_TO_ONE
      bias = 1.0;
#endif
      EscherWord = wordRgb(encodeFloat24(ProjMat[2][2] - bias));
    }
    const vec2 corners[4] = vec2[](vec2(0, 1), vec2(0, 0), vec2(1, 0), vec2(1, 1));
    vec2 pixel =
        vec2(index % PACKET_SIZE.x, int(ScreenSize.y) - 1 - index / PACKET_SIZE.x);
    gl_Position =
        vec4((pixel + corners[gl_VertexIndex % 4]) * 2.0 / ScreenSize - 1.0, 1.0, 1.0);
    return;
  }
