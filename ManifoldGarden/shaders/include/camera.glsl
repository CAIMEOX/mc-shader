#ifndef MANIFOLD_CAMERA
#define MANIFOLD_CAMERA
#include <manifold:packet.glsl>
#include <manifold:rotation.glsl>

float cameraDepthScale() {
#ifdef RENDERPEARL_DEPTH_IS_ZERO_TO_ONE
  return 1.0;
#else
  return 2.0;
#endif
}

// The two physical room envelopes are disjoint along X. Select the room from
// this rendered camera; both logical origins travel in the control packet.
float nativeRoomSlot(vec3 eye) {
  return step(40.0, eye.x);
}

vec3 packetWindowOrigin(sampler2D packet, float slot) {
  if (bits(packet, FIELD_H_LEVEL, 2) == 0u)
    return vec3(0.0);
  uint region =
      slot < .5 ? bits(packet, FIELD_R_WINDOW0, 3) : bits(packet, FIELD_R_WINDOW1, 3);
  return 32.0 * vec3(region & 1u, (region >> 1u) & 1u, (region >> 2u) & 1u);
}

mat3 packetNativeView(sampler2D packet) {
  vec4 q = decodeRotation(uvec2(packetWord(packet, 1), packetWord(packet, 2)));
  return transpose(mat3(rotateVector(q, vec3(1, 0, 0)), rotateVector(q, vec3(0, 1, 0)),
                        rotateVector(q, vec3(0, 0, 1))));
}

mat4 packetProjection(sampler2D packet) {
  mat4 projection;
  for (int column = 0; column < 4; column++)
    for (int row = 0; row < 4; row++)
      projection[column][row] = decodeFloat24(packetWord(packet, 6 + column * 4 + row));
  // Preserve the correlated depth rows through 24-bit transport. For any
  // affine view effect after perspective, clip z = -A * clip w + B * local w.
  float depthA = decodeFloat24(packetWord(packet, 4)) + (cameraDepthScale() - 1.0);
  float depthB = decodeFloat24(packetWord(packet, 5));
  for (int column = 0; column < 4; column++)
    projection[column][2] = -depthA * projection[column][3];
  projection[3][2] += depthB;
  return projection;
}

vec3 projectionEye(mat4 inverseProjection) {
  // A perspective optical centre maps to clip (0, 0, z, 0). Including its
  // inverse transform keeps projection-space view-bob translation in the eye.
  vec4 eye = inverseProjection * vec4(0, 0, 1, 0);
  return eye.xyz / eye.w;
}

vec3 projectionPoint(mat4 inverseProjection, vec2 uv, float depth) {
  float clipDepth = cameraDepthScale() * depth - (cameraDepthScale() - 1.0);
  vec4 point = inverseProjection * vec4(uv * 2.0 - 1.0, clipDepth, 1.0);
  return point.xyz / point.w;
}
#endif
