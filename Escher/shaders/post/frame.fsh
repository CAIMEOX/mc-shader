#version 330
#include <minecraft:globals.glsl>
#include <escher:packet.glsl>
#include <escher:folding_space.glsl>
uniform sampler2D PacketSampler;
uniform sampler2D PreviousSampler;
layout(location = 0) out vec4 fragColor;
float previous(int i) {
  return decodeFloat(texelFetch(PreviousSampler, ivec2(i, 0), 0));
}
void main() {
  int index = int(gl_FragCoord.x);
  if (!presentPacket(PacketSampler)) {
    fragColor = texelFetch(PreviousSampler, ivec2(index, 0), 0);
    return;
  }
  int scene = int(bits(PacketSampler, FIELD_SCENE, 1));
  float target = clamp(float(bits(PacketSampler, FIELD_FOLDING, 10)) / 1000., 0., 1.);
  bool same = previous(3) == float(scene + 1);
  float dt = same ? clamp(mod(GameTime - previous(1) + 1., 1.) * 1200., 0., .1) : 0.;
  float amount = same ? previous(0) : 0., start = same ? previous(4) : 0.,
        elapsed = same ? previous(6) : 0.;
  if (!same || abs(previous(5) - target) > .0001) {
    start = amount;
    elapsed = 0.;
  }
  elapsed = min(elapsed + dt, FOLD_MORPH_SECONDS);
  float duration = max(.8, FOLD_MORPH_SECONDS * abs(target - start));
  float progress = clamp(elapsed / duration, 0., 1.);
  amount = bits(PacketSampler, FIELD_ANIMATE, 1) == 0u
               ? target
               : mix(start, target, .5 - .5 * cos(3.141592653589793 * progress));
  if (scene == 0)
    amount = 0.;
  bool moving = scene == 1 && bits(PacketSampler, FIELD_ROLLING, 1) == 1u;
  float travel = same ? previous(2) : 0., roll = same ? previous(7) : 0.;
  float speed = moving ? FOLD_BALL_SPEED : 0.;
  travel = mod(travel + dt * speed, FOLD_BALL_SPACING);
  float A = 1. - amount * FOLD_RADIUS * FOLD_TURN / FOLD_WIDTH,
        B = -amount * FOLD_HEIGHT / FOLD_WIDTH;
  roll =
      mod(roll + dt * speed * length(vec2(A, B)) / FOLD_BALL_RADIUS, 6.283185307179586);
  float sideRoll = same ? previous(8) : 0.;
  float latitude = amount * 18. * FOLD_WIDTH / 128. / FOLD_RADIUS;
  sideRoll =
      mod(sideRoll + dt * speed * length(vec2(A * cos(latitude), B)) / FOLD_BALL_RADIUS,
          6.283185307179586);
  float value = index == 0   ? amount
                : index == 1 ? GameTime
                : index == 2 ? travel
                : index == 3 ? float(scene + 1)
                : index == 4 ? start
                : index == 5 ? target
                : index == 6 ? elapsed
                : index == 7 ? roll
                             : sideRoll;
  fragColor = encodeFloat(value);
}
