#version 330
#extension GL_ARB_separate_shader_objects : require
#include <manifold:render_data.glsl>
#include <manifold:gravity_settings.glsl>
#include <manifold:joinery_style.glsl>
#include <manifold:joinery_hud.glsl>
uniform sampler2D InSampler;
layout(location = 0) out vec4 fragColor;
float luminance(vec3 color) {
  return dot(color, vec3(.2126, .7152, .0722));
}
vec3 imageColor(vec2 uv, vec2 pixel) {
  return texture(InSampler, clamp(uv, pixel * .5, 1.0 - pixel * .5)).rgb;
}
vec3 antialias(vec2 uv, vec2 pixel) {
  vec3 centre = imageColor(uv, pixel);
  vec3 cnw = imageColor(uv + pixel * vec2(-1, -1), pixel),
       cne = imageColor(uv + pixel * vec2(1, -1), pixel);
  vec3 csw = imageColor(uv + pixel * vec2(-1, 1), pixel),
       cse = imageColor(uv + pixel * vec2(1, 1), pixel);
  float nw = luminance(cnw), ne = luminance(cne), sw = luminance(csw),
        se = luminance(cse);
  float middle = luminance(centre), low = min(middle, min(min(nw, ne), min(sw, se))),
        high = max(middle, max(max(nw, ne), max(sw, se)));
  if (high - low < max(.012, high * .055))
    return centre;
  vec2 direction = vec2(-(nw + ne - sw - se), nw + sw - ne - se);
  float reduction = max((nw + ne + sw + se) * .03125, .0078125);
  direction = clamp(direction / (min(abs(direction.x), abs(direction.y)) + reduction),
                    vec2(-6), vec2(6)) *
              pixel;
  vec3 inner = .5 * (imageColor(uv - direction / 6.0, pixel) +
                     imageColor(uv + direction / 6.0, pixel));
  vec3 outer = inner * .5 + .25 * (imageColor(uv - direction * .5, pixel) +
                                   imageColor(uv + direction * .5, pixel));
  float value = luminance(outer);
  vec3 filtered = value < low || value > high ? inner : outer;
  float subpixel = abs(middle - (nw + ne + sw + se) * .25) / max(high - low, .001);
  subpixel = smoothstep(0.0, 1.0, subpixel);
  return mix(filtered, (cnw + cne + csw + cse) * .25, subpixel * subpixel * .35);
}
void main() {
  vec2 size = vec2(textureSize(InSampler, 0)), uv = gl_FragCoord.xy / size;
  fragColor = texelFetch(InSampler, ivec2(gl_FragCoord.xy), 0);
  if (FrameReady < .5 || Level < .5 || Level > 1.5 ||
      texelFetch(PacketSampler, ivec2(0), 0).a < .9)
    return;
  fragColor = joineryHud(vec4(antialias(uv, 1.0 / size), 1), gl_FragCoord.xy, size);
}
