#version 330
#extension GL_ARB_separate_shader_objects : require
#include <flame:volume.glsl>
uniform sampler2D MainSampler;
uniform sampler2D DepthSampler;
uniform sampler2D VolumeSampler;
uniform sampler2D GuideSampler;
uniform sampler2D ThermalSampler;
uniform sampler2D SolidSampler;
layout(location = 0) out vec4 fragColor;
void main() {
  ivec2 pixel = ivec2(gl_FragCoord.xy), size = textureSize(MainSampler, 0);
  vec3 background = texelFetch(MainSampler, pixel, 0).rgb;
  fragColor = vec4(background, 1);
  int top = size.y - 1 - pixel.y;
  if (pixel.x < PACKET_SIZE.x && top >= 0 &&
      top * PACKET_SIZE.x + pixel.x < PACKET_WORDS) {
    fragColor.rgb =
        texelFetch(MainSampler, ivec2(pixel.x, size.y - 1 - PACKET_SIZE.y), 0).rgb;
    return;
  }
  if (FrameReady < .5)
    return;
  float depth = sceneDistance(DepthSampler, texCoord);
  vec3 ray = worldRay(texCoord);
  float start, end;
  vec4 volume = vec4(0);
  if (volumeInterval(RayOrigin, ray, depth, start, end)) {
    ivec2 small = textureSize(VolumeSampler, 0);
    vec2 p = texCoord * vec2(small) - .5, f = fract(p);
    ivec2 base = ivec2(floor(p));
    float weights = 0;
    for (int y = 0; y < 2; y++)
      for (int x = 0; x < 2; x++) {
        ivec2 q = clamp(base + ivec2(x, y), ivec2(0), small - 1);
        float guide = decodeFloat(texelFetch(GuideSampler, q, 0));
        vec2 w = mix(1.0 - f, f, vec2(x, y));
        float weight = w.x * w.y * exp(-abs(guide - depth) / max(.08, .008 * depth));
        volume += weight * texelFetch(VolumeSampler, q, 0);
        weights += weight;
      }
    volume = weights > .08 ? volume / weights : traceVolume(texCoord, depth, false);
  }
  vec3 point = RayOrigin + ray * (depth + .025);
  ivec3 cell = ivec3(floor(point / CELL_SIZE));
  if (inGrid(cell)) {
    int i = cellIndex(cell);
    vec4 scene = texelFetch(SolidSampler, address(i), 0);
    int material = int(round(scene.g * 255.0));
    if (scene.r > .5 && material > 0 && scene.b > 0.0) {
      float fuel = decodeFloat(texelFetch(ThermalSampler, address(i), 0)),
            heat = decodeFloat(texelFetch(ThermalSampler, address(i + CELLS), 0));
      float charred = clamp(1.0 - fuel / FUEL_LOAD[material], 0.0, 1.0);
      background *= mix(1.0, .2, smoothstep(.05, .85, charred));
      background +=
          vec3(1, .12, .008) * charred * smoothstep(650.0, 1050.0, heat) * .32;
      if (heat > 500.0) {
        vec4 nearby = volumeField(RayOrigin + ray * max(0.0, depth - .25));
        background += fireColor(AMBIENT + nearby.r * 2000.0) * nearby.b * .35;
      }
    }
  }
  vec3 emission = volume.rgb / max(vec3(.015), 1.0 - volume.rgb);
  fragColor.rgb =
      clamp(1.0 - (1.0 - background * (1.0 - volume.a)) * exp(-emission), 0.0, 1.0);
}
