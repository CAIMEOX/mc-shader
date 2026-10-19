#include <manifold:gravity_settings.glsl>
#include <manifold:rotation.glsl>
#include <manifold:camera.glsl>

vec4 gravitySlerp(vec4 a, vec4 b, float t) {
  float cosine = dot(a, b);
  if (cosine < 0.0) {
    b = -b;
    cosine = -cosine;
  }
  if (cosine > .9995)
    return normalize(mix(a, b, t));
  float angle = acos(clamp(cosine, -1.0, 1.0));
  return (sin((1.0 - t) * angle) * a + sin(t * angle) * b) / sin(angle);
}

vec3 priorPosition(int offset) {
  return vec3(previous(offset), previous(offset + 1), previous(offset + 2));
}
vec4 priorQuaternion(int offset) {
  return vec4(previous(offset), previous(offset + 1), previous(offset + 2),
              previous(offset + 3));
}

float gravityFrame(int index) {
  float epoch = float(bits(PacketSampler, FIELD_G_EPOCH, 16));
  float sequence = float(bits(PacketSampler, FIELD_G_SEQ, 16));
  float frame = float(bits(PacketSampler, FIELD_G_FRAME, 5));
  float mode = float(bits(PacketSampler, FIELD_H_MODE, 2));
  float period = float(bits(PacketSampler, FIELD_PERIOD, 8));
  bool same = previous(3) == 1.0 && previous(30) == epoch;
  float dt =
      same ? clamp(mod(GameTime - previous(1) + 1.0, 1.0) * 1200.0, 0.0, .1) : 0.0;
  vec3 target =
      vec3(bits(PacketSampler, FIELD_G_X, 18), bits(PacketSampler, FIELD_G_Y, 18),
           bits(PacketSampler, FIELD_G_Z, 18)) /
      GRAVITY_UNIT;
  vec3 start = same ? priorPosition(14) : target;
  vec3 end = same ? priorPosition(17) : target;
  float elapsed = same ? previous(10) + dt : .05;
  if (same && (previous(9) != sequence || (previous(0) == 1.0 && mode == 2.0))) {
    start = priorPosition(11);
    // Interpolate in the nearest covering-space image, then fold for storage.
    end = start + mod(target - start + period * .5, period) - period * .5;
    elapsed = 0.0;
  }
  vec3 position = mod(mix(start, end, clamp(elapsed / .05, 0.0, 1.0)), period);
  vec4 goal = basisQuaternion(gravityBasis(int(frame)));
  vec4 from = same ? priorQuaternion(24) : goal;
  float turnTime = same ? previous(29) + dt : GRAVITY_TURN_SECONDS;
  if (same && previous(28) != frame) {
    from = priorQuaternion(20);
    turnTime = 0.0;
  }
  float t = clamp(turnTime / GRAVITY_TURN_SECONDS, 0.0, 1.0);
  vec4 orientation = gravitySlerp(from, goal, t * t * (3.0 - 2.0 * t));
  if (mode == 1.0) {
    mat3 basis = gravityBasis(int(frame));
    vec3 nativeEye = vec3(CameraBlockPos) - CameraOffset;
    float slot = nativeRoomSlot(nativeEye);
    vec3 roomOrigin = vec3(slot * 80.0 + .5, 200.5, .5);
    mat4 inverseProjection = inverse(packetProjection(PacketSampler));
    vec3 eye =
        basis * (nativeEye - roomOrigin +
                 packetNativeView(PacketSampler) * projectionEye(inverseProjection));
    vec3 window = packetWindowOrigin(PacketSampler, slot);
    position = eye + window - basis[1] * GRAVITY_EYE_HEIGHT;
    start = position;
    end = position;
    orientation = goal;
    from = goal;
    turnTime = GRAVITY_TURN_SECONDS;
  }
  if (index == 0)
    return mode;
  if (index == 1)
    return GameTime;
  if (index == 2)
    return texelFetch(PacketSampler, ivec2(0), 0).a > .9 ? GameTime : previous(2);
  if (index == 3)
    return 1.0;
  if (index == 9)
    return sequence;
  if (index == 10)
    return min(elapsed, .1);
  if (index >= 11 && index <= 13)
    return position[index - 11];
  if (index >= 14 && index <= 16)
    return start[index - 14];
  if (index >= 17 && index <= 19)
    return end[index - 17];
  if (index >= 20 && index <= 23)
    return orientation[index - 20];
  if (index >= 24 && index <= 27)
    return from[index - 24];
  if (index == 28)
    return frame;
  if (index == 29)
    return min(turnTime, GRAVITY_TURN_SECONDS);
  if (index == 30)
    return epoch;
  if (index == 31)
    return float(bits(PacketSampler, FIELD_G_FLY, 1));
  return 0.0;
}
