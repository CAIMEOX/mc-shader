#ifndef MANIFOLD_JOINERY_HUD
#define MANIFOLD_JOINERY_HUD
float joineryStroke(vec2 p, vec2 a, vec2 b, float width) {
  vec2 v = b - a;
  float t = clamp(dot(p - a, v) / dot(v, v), 0.0, 1.0);
  return 1.0 - smoothstep(width - .35, width + .35, length(p - a - v * t));
}
float joineryAxisLetter(vec2 p, int axis) {
  if (axis == 0)
    return max(joineryStroke(p, vec2(0, 0), vec2(7, 12), .7),
               joineryStroke(p, vec2(7, 0), vec2(0, 12), .7));
  if (axis == 1)
    return max(max(joineryStroke(p, vec2(0, 0), vec2(3.5, 6), .7),
                   joineryStroke(p, vec2(7, 0), vec2(3.5, 6), .7)),
               joineryStroke(p, vec2(3.5, 6), vec2(3.5, 12), .7));
  return max(max(joineryStroke(p, vec2(0, 0), vec2(7, 0), .7),
                 joineryStroke(p, vec2(7, 0), vec2(0, 12), .7)),
             joineryStroke(p, vec2(0, 12), vec2(7, 12), .7));
}
float joineryDigit(vec2 p, int digit) {
  const int segments[6] = int[](6, 91, 79, 102, 109, 125);
  const vec2 start[7] = vec2[](vec2(1, 0), vec2(6, 1), vec2(6, 7), vec2(1, 12),
                               vec2(0, 7), vec2(0, 1), vec2(1, 6));
  const vec2 end[7] = vec2[](vec2(5, 0), vec2(6, 5), vec2(6, 11), vec2(5, 12),
                             vec2(0, 11), vec2(0, 5), vec2(5, 6));
  float mask = 0.0;
  for (int i = 0; i < 7; i++)
    if ((segments[clamp(digit - 1, 0, 5)] & (1 << i)) != 0)
      mask = max(mask, joineryStroke(p, start[i], end[i], .65));
  return mask;
}
vec4 joineryHud(vec4 scene, vec2 pixel, vec2 size) {
  if (Level < .5 || Level > 1.5 || FrameReady < .5)
    return scene;
  float scale = clamp(size.y / 700.0, 1.0, 2.0);
  vec2 q = vec2(pixel.x, size.y - pixel.y) / scale - vec2(size.x / scale - 148.0, 16.0);
  vec2 d = abs(q - vec2(64, 17)) - vec2(61, 14);
  float edge = length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - 3.0;
  if (edge > .7)
    return scene;
  float mask = 1.0 - smoothstep(-.4, .6, edge);
  vec3 color = mix(scene.rgb, vec3(.105, .119, .109), .64 * mask);
  color = mix(color, vec3(.72, .70, .61), .18 * mask * smoothstep(-1.3, -.4, edge));
  vec3 ink = vec3(.90, .88, .80), muted = vec3(.63, .70, .65);
  vec3 down = -gravityBasis(int(GravityData.y))[1];
  int axis = abs(down.x) > .5 ? 0 : abs(down.y) > .5 ? 1 : 2;
  float arrow = max(joineryStroke(q, vec2(15, 10), vec2(15, 24), .6),
                    max(joineryStroke(q, vec2(10, 19), vec2(15, 24), .6),
                        joineryStroke(q, vec2(20, 19), vec2(15, 24), .6)));
  color = mix(color, muted, arrow);
  float sign = joineryStroke(q, vec2(31, 17), vec2(39, 17), .65);
  if (down[axis] > 0.0)
    sign = max(sign, joineryStroke(q, vec2(35, 13), vec2(35, 21), .65));
  color = mix(color, ink, max(sign, joineryAxisLetter(q - vec2(46, 11), axis)));
  bool moving = JoineryMotion.x >= 0.0;
  int id = moving ? int(JoineryMotion.x) : int(JoineryFocus.x);
  if (id >= 0) {
    float swatch = 1.0 - smoothstep(3.4, 4.0, length(q - vec2(79, 17)));
    color = mix(color, joineryPalette(id), swatch);
    color = mix(color, ink, joineryDigit(q - vec2(91, 11), id + 1));
    vec2 s = q - vec2(113, 17);
    float status;
    if (JoineryFocus.w > .5 || moving)
      status = max(joineryStroke(s, vec2(-3, 0), vec2(-.5, 2.5), .6),
                   joineryStroke(s, vec2(-.5, 2.5), vec2(4, -3), .6));
    else
      status = max(joineryStroke(s, vec2(-3, -3), vec2(3, 3), .6),
                   joineryStroke(s, vec2(-3, 3), vec2(3, -3), .6));
    color =
        mix(color,
            JoineryFocus.w > .5 || moving ? vec3(.64, .76, .65) : vec3(.76, .61, .43),
            status);
  } else if (JoineryMotion.z > .5) {
    float square = max(joineryStroke(q, vec2(95, 12), vec2(95, 23), .7),
                       joineryStroke(q, vec2(95, 12), vec2(106, 12), .7));
    color = mix(color, muted, square);
  }
  if (moving)
    color = mix(color, ink * .8,
                joineryStroke(q, vec2(12, 30),
                              vec2(12 + 104 * max(.001, JoineryMotion.w), 30), .45));
  return vec4(color, 1);
}
#endif
