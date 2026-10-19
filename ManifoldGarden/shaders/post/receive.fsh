#version 330
#include <minecraft:globals.glsl>
#include <manifold:packet.glsl>
uniform sampler2D MainSampler;
uniform sampler2D PreviousSampler;
uniform sampler2D FrameSampler;
layout(location = 0) out vec4 fragColor;
void main() {
  ivec2 size = textureSize(MainSampler, 0), p = ivec2(gl_FragCoord.xy);
  ivec2 origin = ivec2(0, size.y - 1);
  if (presentPacketAt(MainSampler, origin)) {
    fragColor = vec4(texelFetch(MainSampler, origin + ivec2(p.x, 0), 0).rgb, 1.0);
    return;
  }
  float lastFresh = decodeFloat(texelFetch(FrameSampler, ivec2(2, 0), 0));
  float age = mod(GameTime - lastFresh + 1.0, 1.0) * 1200.0;
  // Preserve the complete camera/controller packet across brief draw-list gaps.
  // Expiry also releases a stopped session when its final carrier was not drawn.
  fragColor = validPacket(PreviousSampler) && age < .75
                  ? vec4(texelFetch(PreviousSampler, p, 0).rgb, .75)
                  : vec4(0);
}
