#version 330
#extension GL_ARB_separate_shader_objects : require
#include <minecraft:globals.glsl>
uniform sampler2D PacketSampler;
uniform sampler2D ControlSampler;
#define FLAME_RENDER_VERTEX
#include <flame:render_data.glsl>
void main() {
  vec2 uv = vec2((gl_VertexIndex << 1) & 2, gl_VertexIndex & 2);
  gl_Position = vec4(uv * 2.0 - 1.0, 0, 1);
  texCoord = uv;
  FrameReady = validPacket(PacketSampler) ? 1.0 : 0.0;
  RayOrigin = vec3(CameraBlockPos - regionOrigin(PacketSampler)) - CameraOffset;
  vec4 q =
      decodeRotation(uvec2(packetWord(PacketSampler, 1), packetWord(PacketSampler, 2)));
  InverseView =
      transpose(mat3(rotateVector(q, vec3(1, 0, 0)), rotateVector(q, vec3(0, 1, 0)),
                     rotateVector(q, vec3(0, 0, 1))));
  float scale = decodeFloat24(packetWord(PacketSampler, 3)),
        depth = decodeFloat24(packetWord(PacketSampler, 4)) + projectionBias();
  InverseProjection = inverse(mat4(vec4(scale * ScreenSize.y / ScreenSize.x, 0, 0, 0),
                                   vec4(0, scale, 0, 0), vec4(0, 0, depth, -1),
                                   vec4(0, 0, .05 * (depth + 1.0), 0)));
  SimulationTime = float(decodeUint(texelFetch(ControlSampler, ivec2(4, 0), 0))) * DT;
}
