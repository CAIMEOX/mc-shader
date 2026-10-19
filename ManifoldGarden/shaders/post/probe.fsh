#version 330
#extension GL_ARB_separate_shader_objects : require
#include <manifold:render_data.glsl>
#include <manifold:gravity_settings.glsl>
#include <manifold:hybrid_render.glsl>
#include <manifold:gravity_render.glsl>
#include <manifold:joinery_illumination.glsl>
uniform sampler2D FrameSampler;
uniform sampler2D DepthSampler;
layout(location = 0) out vec4 fragColor;
void main() {
  int i = int(gl_FragCoord.x);
  if (int(gl_FragCoord.y) > 0) {
    int channel = i % 8;
    vec2 uv = (vec2(i / 8, int(gl_FragCoord.y) - 1) + .5) / vec2(32, 18);
    ivec2 size = textureSize(DepthSampler, 0);
    ivec2 pixel = clamp(ivec2(uv * vec2(size)), ivec2(0), size - 1);
    uv = (vec2(pixel) + .5) / vec2(size);
    vec3 direction = worldRay(uv);
    float depth = texelFetch(DepthSampler, pixel, 0).r;
    bool physical = nativePixel(DepthSampler, uv);
    float distance = nativeRayDistance(depth, uv), travel;
    vec3 p;
    float traced = traceArchitecture(RayOrigin, direction, 540.0, 224, p, travel)
                       ? dot(p - RayOrigin, direction)
                       : 1e7;
    float value =
        channel == 0   ? (physical ? distance : traced)
        : channel == 1 ? float(physical)
        : channel == 2 ? traced
        : channel < 6  ? direction[channel - 3]
        : channel == 6
            ? (physical ? sceneGeometryDistance(nativeWorldPoint(uv, depth)) : 0.0)
            : distance;
    fragColor = encodeFloat(value);
    return;
  }
  float value = 0.0;
  if (i < 3)
    value = RayOrigin[i];
  else if (i < 12)
    value = InverseView[(i - 3) / 3][(i - 3) % 3];
  else if (i == 12)
    value = FrameReady;
  else if (i == 13)
    value = GravityData.x;
  else if (i == 14)
    value = GravityData.y;
  else if (i == 15)
    value = FrameReady;
  else if (i < 48)
    value = decodeFloat(texelFetch(FrameSampler, ivec2(i - 16, 0), 0));
  else if (i == 48)
    value = HybridData.x;
  else if (i == 51)
    value = HybridData.y;
  else if (i == 72)
    value = Level;
  else if (i == 80 || i == 81) {
    bool energized = i == 81;
    vec3 arrow = cubeEnamel(vec3(-.076, -.16, .5), vec3(0, 0, 1), RINGS_GRAVITY[1],
                            ringsPalette(1), energized, .002);
    vec3 field = cubeEnamel(vec3(.05, -.16, .5), vec3(0, 0, 1), RINGS_GRAVITY[1],
                            ringsPalette(1), energized, .002);
    value = length(arrow - field);
  } else if (i == 85) {
    vec3 p = vec3(10.21, .5, 4.27), n = vec3(0, 1, 0), shift = vec3(64, -128, 192);
    vec3 a = architectureStone(.005, stoneSurfaceFinish(p, n, .005).w);
    vec3 b = architectureStone(.005, stoneSurfaceFinish(p + shift, n, .005).w);
    value = length(a - b);
  } else if (i == 86) {
    vec3 p = vec3(10.21, .5, 4.27), n = vec3(0, 1, 0), shift = vec3(.001, 0, .001);
    vec3 a = architectureStone(.5, stoneSurfaceFinish(p, n, .5).w);
    vec3 b = architectureStone(.5, stoneSurfaceFinish(p + shift, n, .5).w);
    value = length(a - b);
  } else if (i >= 87 && i <= 90) {
    value = i == 90 ? 0.0 : 10.0;
    for (int cube = 0; cube < OBJECT_COUNT; cube++) {
      vec3 gravity = RINGS_GRAVITY[cube];
      vec3 up = -gravity;
      vec3 vertical = abs(gravity.y) > .5 ? vec3(0, 0, 1) : vec3(0, 1, 0);
      vec3 n = (i == 88 || i == 90) ? -up : up;
      vec3 right = cross(vertical, n);
      vec2 mark = i == 87 || i == 90 ? vec2(.08) : (i == 88 ? vec2(0) : vec2(.17, 0));
      vec3 a = cubeEnamel(n * .5 + right * mark.x + vertical * mark.y, n, gravity,
                          ringsPalette(cube), false, .002);
      vec3 b =
          cubeEnamel(n * .5 + right * .10, n, gravity, ringsPalette(cube), false, .002);
      float contrast = length(a - b);
      value = i == 90 ? max(value, contrast) : min(value, contrast);
    }
  } else if (i >= 91 && i <= 93) {
    mat3 worldOrientation = InverseView * heldCubeRotation();
    value = length(worldOrientation[i - 91] - mat3(1.0)[i - 91]);
  } else if (i == 94 || i == 95) {
    vec4 projected = inverse(InverseProjection) *
                     vec4(projectionEye(InverseProjection) + HELD_CUBE_CENTRE, 1.0);
    vec4 held;
    bool visible = ringsHeld(projected.xy / projected.w * .5 + .5, held);
    value = i == 94 ? (visible ? 1.0 : 0.0) : (visible ? length(held.rgb) : 0.0);
  } else if (i >= 96 && i < 99) {
    value = WindowOrigin[i - 96];
  } else if (i >= 99 && i < 103) {
    value = RingsData[i - 99];
  } else if (i >= 103 && i < 112) {
    value = ringsCube((i - 103) / 3)[(i - 103) % 3];
  } else if (i >= 112 && i < 115) {
    value = float(ringsPhase(i - 112));
  } else if (i == 115) {
    value = ringsDistance(vec3(8, 63, 4));
  } else if (i == 131) {
    value = JoineryFocus.x;
  } else if (i == 134) {
    value = float(JoineryBlocker);
  } else if (i >= 135 && i < 153) {
    value = joineryShift((i - 135) / 3)[(i - 135) % 3];
  } else if (i >= 153 && i < 156) {
    value = (-gravityBasis(int(GravityData.y))[1])[i - 153];
  } else if (i == 156) {
    value = architectureHaze(256.0);
  } else if (i == 157) {
    value = 10.0;
    for (int a = 0; a < 6; a++)
      for (int b = a + 1; b < 6; b++)
        value = min(value, length(joineryPalette(a) - joineryPalette(b)));
  } else if (i == 158) {
    value = JoineryMotion.z;
  } else if (i == 159) {
    value = JoineryFocus.y;
  } else if (i == 160) {
    vec3 p = vec3(52, 39.5, 32) + joineryShift(1);
    vec3 a = joinerySurface(p, vec3(0, 1, 0), .002).albedo;
    vec3 b = joinerySurface(p + vec3(.85, 0, 0), vec3(0, 1, 0), .002).albedo;
    value = length(a - b);
  } else if (i == 161) {
    vec3 p = vec3(45, 39.5, 32) + joineryShift(1);
    value = length(joineryIllumination(p, vec3(0, 1, 0)) -
                   joineryIllumination(p + vec3(64, -64, 128), vec3(0, 1, 0)));
  } else if (i == 162) {
    vec3 a = joineryPalette(0), b = joineryPalette(4);
    value = length(joineryAtmosphere(a, a, vec3(0, 1, 0), 256.0) -
                   joineryAtmosphere(b, b, vec3(0, 1, 0), 256.0)) /
            length(a - b);
  } else if (i == 163) {
    for (int step = 0; step < 20; step++) {
      float d = float(step) * 32.0;
      vec3 color = joineryPalette(0);
      value =
          max(value, length(joineryAtmosphere(color, color, vec3(0, 1, 0), d + .01) -
                            joineryAtmosphere(color, color, vec3(0, 1, 0), d - .01)));
    }
  } else if (i == 164) {
    for (int sampleId = 0; sampleId < 32; sampleId++) {
      vec3 p = mod(vec3(11.31, 7.17, 17.43) * float(sampleId) + vec3(23.5, 19.5, 27.5),
                   64.0);
      if (sampleId < 16)
        p = vec3(23.5) + mod(vec3(3, 5, 7) * float(sampleId), 16.0);
      float reference = 1e6;
      for (int member = 0; member < 6; member++)
        reference = min(reference, joineryRodDistance(p, member));
      value = max(value, abs(joineryDistance(p) - reference));
    }
  } else {
    ivec2 size = textureSize(DepthSampler, 0);
    ivec2 center = size / 2;
    vec2 uv = (vec2(center) + .5) / vec2(size);
    float depth = texelFetch(DepthSampler, center, 0).r;
    float distance = nativeRayDistance(depth, uv);
    if (i == 53)
      value = depth;
    else if (i == 54)
      value = distance;
    else if (i == 55)
      value = nativePixel(DepthSampler, uv) ? 1.0 : 0.0;
    else if (i >= 56 && i < 59)
      value = depth > 1e-8 ? nativeWorldPoint(uv, depth)[i - 56] : 0.0;
    else if (i == 59) {
      for (int y = 0; y < 8; y++)
        for (int x = 0; x < 8; x++)
          value +=
              nativePixel(DepthSampler, (vec2(x, y) + .5) / 8.0) ? 1.0 / 64.0 : 0.0;
    } else if (i >= 60 && i < 63)
      value = DepthProjection[i - 60];
    else if (i == 63)
      value = nativeWindowInterval(RayOrigin, worldRay(uv)).y;
    else if (i >= 64 && i < 67) {
      vec3 p = nativeDepthPoint(DepthSampler, center);
      float ambient;
      vec3 n = nativeSurfaceNormal(DepthSampler, center, ambient);
      value = architectureSurface(p, n, length(p - RayOrigin), float(size.y), ambient,
                                  uv)[i - 64];
    } else if (i >= 67 && i < 70)
      value = nativeSurfaceNormal(DepthSampler, center)[i - 67];
    else if (i == 70)
      value = mod(decodeFloat(texelFetch(FrameSampler, ivec2(1, 0), 0)) -
                      decodeFloat(texelFetch(FrameSampler, ivec2(2, 0), 0)) + 1.0,
                  1.0) *
              1200.0;
  }
  fragColor = encodeFloat(value);
}
