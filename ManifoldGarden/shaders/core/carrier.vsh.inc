
#include <minecraft:globals.glsl>
#include <manifold:settings.glsl>
#include <manifold:codec.glsl>
#include <manifold:rotation.glsl>
uniform sampler2D Sampler0;
layout(location = 10) flat out int ManifoldCarrier;
layout(location = 11) flat out vec3 ManifoldWord;
void main() {
  vec4 marker = texelFetch(Sampler0, ivec2(UV0 * vec2(textureSize(Sampler0, 0))), 0);
  int index = int(round(marker.r * 255.0)) + 256 * int(round(marker.g * 255.0));
  ManifoldCarrier = int(abs(marker.b * 255.0 - 239.0) < .1 &&
                        abs(marker.a * 255.0 - 247.0) < .1 && index < PACKET_WORDS);
  ManifoldWord = Color.rgb;
  if (ManifoldCarrier != 0) {
    if (index == 0)
      ManifoldWord = wordRgb(MAGIC);
    if (index == 1 || index == 2) {
      mat3 basis = mat3(normalize(ModelViewMat[0].xyz), normalize(ModelViewMat[1].xyz),
                        normalize(ModelViewMat[2].xyz));
      uvec2 rotation = encodeRotation(basisQuaternion(basis));
      ManifoldWord = wordRgb(index == 1 ? rotation.x : rotation.y);
    }
    if (index == 3)
      ManifoldWord = wordRgb(encodeFloat24(ProjMat[1][1]));
    if (index == 4 || index == 5) {
      float bias = 0.0;
#ifndef RENDERPEARL_DEPTH_IS_ZERO_TO_ONE
      bias = 1.0;
#endif
      int axis = abs(ProjMat[0][3]) > abs(ProjMat[1][3]) ? 0 : 1;
      if (abs(ProjMat[2][3]) > abs(ProjMat[axis][3]))
        axis = 2;
      float depthA = -ProjMat[axis][2] / ProjMat[axis][3];
      float depthB = ProjMat[3][2] + depthA * ProjMat[3][3];
      ManifoldWord = wordRgb(encodeFloat24(index == 4 ? depthA - bias : depthB));
    }
    if (index >= 6 && index < 22)
      ManifoldWord = wordRgb(encodeFloat24(ProjMat[(index - 6) / 4][(index - 6) % 4]));
    const vec2 corners[4] = vec2[](vec2(0, 1), vec2(0, 0), vec2(1, 0), vec2(1, 1));
    vec2 pixel =
        vec2(index % PACKET_SIZE.x, int(ScreenSize.y) - 1 - index / PACKET_SIZE.x);
    gl_Position =
        vec4((pixel + corners[gl_VertexIndex % 4]) * 2.0 / ScreenSize - 1.0, 1.0, 1.0);
    return;
  }
