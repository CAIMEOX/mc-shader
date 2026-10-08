#version 330
#extension GL_ARB_separate_shader_objects : require
#include <minecraft:globals.glsl>
#define BACKROOMS_RENDER_VERTEX
#include <backrooms:render_data.glsl>
#include <backrooms:geometry.glsl>
uniform sampler2D PacketSampler;
void main() {
  vec2 uv = vec2((gl_VertexIndex << 1) & 2, gl_VertexIndex & 2);
  gl_Position = vec4(uv * 2.0 - 1.0, 0, 1);
  texCoord = uv;
  FrameReady = validPacket(PacketSampler) ? 1.0 : 0.0;
  vec3 worldEye = vec3(CameraBlockPos) - CameraOffset;
  RoomId = worldEye.x > HALL_ORIGIN.x - 32.0 ? 1.0 : 0.0;
  RayOrigin = worldEye - (RoomId > .5 ? HALL_ORIGIN : vec3(0, FLOOR_Y, 0));
  if (RoomId < .5)
    RayOrigin.z = mod(RayOrigin.z, ROOM_PERIOD);
  if (RoomId < .5 && RayOrigin.x >= CORRIDOR_HALF_WIDTH &&
      abs(RayOrigin.z - 12.0) < DOOR_HALF_WIDTH && RayOrigin.y < DOOR_HEIGHT) {
    RayOrigin += PORTAL_SHIFT;
    RoomId = 1.0;
  } else if (RoomId > .5 && RayOrigin.x < -HALL_HALF_WIDTH &&
             abs(RayOrigin.z) < DOOR_HALF_WIDTH && RayOrigin.y < DOOR_HEIGHT) {
    RayOrigin -= PORTAL_SHIFT;
    RoomId = 0.0;
  }
  MirrorState = float(bits(PacketSampler, FIELD_MIRROR, 1));
  vec4 q =
      decodeRotation(uvec2(packetWord(PacketSampler, 1), packetWord(PacketSampler, 2)));
  InverseView =
      transpose(mat3(rotateVector(q, vec3(1, 0, 0)), rotateVector(q, vec3(0, 1, 0)),
                     rotateVector(q, vec3(0, 0, 1))));
  float scale = decodeFloat24(packetWord(PacketSampler, 3));
  Projection = vec2(scale * ScreenSize.y / ScreenSize.x, scale);
  DepthProjection = vec3(decodeFloat24(packetWord(PacketSampler, 4)),
                         decodeFloat24(packetWord(PacketSampler, 5)),
                         packetWord(PacketSampler, 6) == 1u ? 1.0 : 2.0);
}
