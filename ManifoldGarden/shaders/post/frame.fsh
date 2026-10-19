#version 330
#include <minecraft:globals.glsl>
#include <manifold:packet.glsl>
uniform sampler2D PacketSampler;
uniform sampler2D PreviousSampler;
layout(location = 0) out vec4 fragColor;
float previous(int i) {
  return decodeFloat(texelFetch(PreviousSampler, ivec2(i, 0), 0));
}
#include <manifold:gravity_frame.glsl>
void main() {
  int index = int(gl_FragCoord.x);
  fragColor = presentPacket(PacketSampler)
                  ? encodeFloat(gravityFrame(index))
                  : texelFetch(PreviousSampler, ivec2(index, 0), 0);
}
