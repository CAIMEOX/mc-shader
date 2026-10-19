#ifndef MANIFOLD_ARCHITECTURE_MATERIAL
#define MANIFOLD_ARCHITECTURE_MATERIAL
#include <manifold:gravity_settings.glsl>
#include <manifold:hybrid_render.glsl>
#include <manifold:cube_material.glsl>
#include <manifold:rings_material.glsl>
#include <manifold:joinery_material.glsl>
#include <manifold:joinery_lightmap.glsl>

const vec3 ARCHITECTURE_SKY = vec3(.925, .950, .945);
vec3 architectureSky() {
  return Level > .5 && Level < 1.5 ? JOINERY_SKY : ARCHITECTURE_SKY;
}
float architectureHaze(float travel) {
  return Level > .5 && Level < 1.5 ? joineryDepthBlend(travel)
                                   : 1.0 - exp(-travel * .0068);
}

vec3 architectureStone(float footprint, float edgeDistance) {
  vec3 stone = vec3(.925, .938, .917);
  float aa = max(.0015, footprint);
  float contour = smoothstep(-aa, aa, edgeDistance + .018) -
                  smoothstep(-aa, aa, edgeDistance - .018);
  return mix(stone, vec3(.24, .34, .33), contour * .42);
}

vec3 architectureSurface(vec3 p, vec3 n, float travel, float height, float ao,
                         vec2 uv) {
  float footprint = max(.0015, travel / (height * Projection.y));
  if (Level > .5 && Level < 1.5) {
    JoinerySurface surface = joinerySurface(p, n, footprint);
    vec2 light = joineryLightAt(uv, travel);
    vec3 normal = surface.normal;
    float noL = max(dot(normal, JOINERY_LIGHT), 0.0);
    vec3 ambient =
        mix(vec3(.42, .44, .43), vec3(.74, .77, .73), normal.y * .5 + .5) * light.y;
    vec3 illumination = ambient + vec3(1.7, 1.59, 1.40) * noL * light.x;
    vec3 color = pow(surface.albedo, vec3(2.2)) * illumination;
    vec3 view = normalize(RayOrigin - p), halfway = normalize(view + JOINERY_LIGHT);
    vec3 grain = vec3(0);
    grain[JOINERY_AXIS[surface.member]] = 1.0;
    vec3 tangent = grain - normal * dot(grain, normal);
    if (dot(tangent, tangent) < .01)
      tangent = cross(normal, abs(normal.y) < .9 ? vec3(0, 1, 0) : vec3(0, 0, 1));
    tangent = normalize(tangent);
    vec3 across = cross(normal, tangent);
    float noH = max(dot(normal, halfway), .001);
    vec2 slope = vec2(dot(halfway, tangent), dot(halfway, across)) / noH;
    float sheen = exp(-dot(slope * slope, vec2(2.5, 5.5)) /
                      (surface.roughness * surface.roughness));
    float fresnel = .035 + .12 * pow(1.0 - max(dot(normal, view), 0.0), 5.0);
    color += vec3(1, .97, .88) * sheen * fresnel * noL * light.x;
    color = pow(1.0 - exp(-color * 1.18), vec3(1.0 / 2.2));
    return joineryAtmosphere(color, surface.albedo, n, travel);
  }
  vec3 color;
  bool object = ringsSurface(p, n, footprint, color);
  vec3 shadingNormal = n;
  if (!object) {
    vec4 finish = stoneSurfaceFinish(p, n, footprint);
    color = architectureStone(footprint, finish.w);
    shadingNormal = finish.xyz;
  }
  vec3 lightDirection = normalize(vec3(-.45, .82, .35));
  float light = .76 + .10 * shadingNormal.y + .14 * dot(shadingNormal, lightDirection);
  vec3 shade = mix(vec3(.88, .945, 1.0), vec3(1.0, .995, .955), clamp(light, 0.0, 1.0));
  color *= light * shade * mix(.82, 1.0, ao);
  vec3 view = normalize(RayOrigin - p);
  float reflection =
      pow(max(0.0, dot(reflect(-lightDirection, shadingNormal), view)), 24.0);
  color += reflection * (object ? .065 : .025) * vec3(1.0, .98, .91);
  return mix(color, architectureSky(), architectureHaze(travel));
}
#endif
