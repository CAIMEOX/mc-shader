#version 330
#extension GL_ARB_separate_shader_objects : require
#include <minecraft:globals.glsl>
#define MANIFOLD_RENDER_VERTEX
#include <manifold:render_data.glsl>
#include <manifold:gravity_settings.glsl>
#include <manifold:surface_finish.glsl>
#include <manifold:joinery_scene.glsl>
uniform sampler2D PacketSampler;
uniform sampler2D FrameSampler;
float state(int i) {
  return decodeFloat(texelFetch(FrameSampler, ivec2(i, 0), 0));
}
void main() {
  vec2 uv = vec2((gl_VertexIndex << 1) & 2, gl_VertexIndex & 2);
  gl_Position = vec4(uv * 2.0 - 1.0, 0, 1);
  texCoord = uv;
  FrameReady = validPacket(PacketSampler) ? 1.0 : 0.0;
  RenderQuality = float(bits(PacketSampler, FIELD_QUALITY, 2));
  mat3 nativeView = packetNativeView(PacketSampler);
  mat4 projection = packetProjection(PacketSampler);
  InverseProjection = inverse(projection);
  Projection = vec2(length(vec3(projection[0][0], projection[1][0], projection[2][0])),
                    length(vec3(projection[0][1], projection[1][1], projection[2][1])));
  DepthProjection =
      vec3(decodeFloat24(packetWord(PacketSampler, 4)),
           decodeFloat24(packetWord(PacketSampler, 5)), cameraDepthScale());
  HybridData = vec2(float(bits(PacketSampler, FIELD_H_MODE, 2)),
                    float(bits(PacketSampler, FIELD_H_SLOT, 1)));
  Level = float(bits(PacketSampler, FIELD_H_LEVEL, 2));
  WindowOrigin = packetWindowOrigin(PacketSampler, HybridData.y);
  RingsData = vec4(float(bits(PacketSampler, FIELD_R_HELD, 10)) - 1.0,
                   float((bits(PacketSampler, FIELD_R_GATES, 16) & 1u)),
                   float(((bits(PacketSampler, FIELD_R_GATES, 16) >> 1u) & 1u)),
                   float(bits(PacketSampler, FIELD_R_COMPLETE, 1)));
  PreviewWord = packetWord(PacketSampler, OBJECT_WORD_OFFSET + OBJECT_COUNT);
  for (int i = 0; i < 4; i++) {
    ObjectCache0[i] =
        i < OBJECT_COUNT ? packetWord(PacketSampler, OBJECT_WORD_OFFSET + i) : 0u;
    ObjectCache1[i] = i + 4 < OBJECT_COUNT
                          ? packetWord(PacketSampler, OBJECT_WORD_OFFSET + i + 4)
                          : 0u;
  }
  uint motion = PreviewWord;
  JoineryMotion = vec4(
      float(motion & 7u) - 1.0, float((motion >> 3u) & 7u), float((motion >> 10u) & 1u),
      clamp((float((motion >> 6u) & 15u) + state(10) * 20.0) / 12.0, 0.0, 1.0));
  vec4 qg = vec4(state(20), state(21), state(22), state(23));
  mat3 basis = mat3(rotateVector(qg, vec3(1, 0, 0)), rotateVector(qg, vec3(0, 1, 0)),
                    rotateVector(qg, vec3(0, 0, 1)));
  RayOrigin = vec3(state(11), state(12), state(13)) + basis[1] * GRAVITY_EYE_HEIGHT;
  InverseView = basis * nativeView;
  if (HybridData.x == 1.0) {
    basis = gravityBasis(int(bits(PacketSampler, FIELD_G_FRAME, 5)));
    vec3 nativeEye = vec3(CameraBlockPos) - CameraOffset;
    HybridData.y = nativeRoomSlot(nativeEye);
    WindowOrigin = packetWindowOrigin(PacketSampler, HybridData.y);
    vec3 roomOrigin = vec3(HybridData.y * 80.0 + .5, 200.5, .5);
    RayOrigin = WindowOrigin + basis * (nativeEye - roomOrigin +
                                        nativeView * projectionEye(InverseProjection));
    InverseView = basis * nativeView;
  }
  GravityData = vec4(state(29), float(bits(PacketSampler, FIELD_G_FRAME, 5)),
                     float(bits(PacketSampler, FIELD_G_FLY, 1)),
                     float(bits(PacketSampler, FIELD_G_GROUNDED, 1)));
  JoineryFocus = vec4(-1, -1, 0, 0);
  JoineryBlocker = -1;
  if (Level > .5 && Level < 1.5 && HybridData.x == 1.0 && JoineryMotion.z > .5) {
    vec3 ray = worldRay(vec2(.5)), normal;
    float distance;
    if (joineryTrace(RayOrigin, ray, 96.0, distance, normal)) {
      int id = joineryMember(RayOrigin + ray * distance);
      ivec3 down = ivec3(-gravityBasis(int(GravityData.y))[1]);
      JoineryBlocker = joineryBlocker(id, down);
      JoineryFocus = vec4(id, distance, 4.0, JoineryBlocker < 0 ? 1.0 : 0.0);
    }
  }
}
