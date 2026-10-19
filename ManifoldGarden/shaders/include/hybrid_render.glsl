#ifndef MANIFOLD_HYBRID_RENDER
#define MANIFOLD_HYBRID_RENDER
#include <manifold:stage_scene.glsl>
#include <manifold:rings_scene.glsl>
#include <manifold:joinery_scene.glsl>

bool exactSceneTrace(vec3 ro, vec3 rd, float limit, out float travel, out vec3 normal) {
  return Level < 1.5 ? joineryTrace(ro, rd, limit, travel, normal)
                     : ringsTrace(ro, rd, limit, travel, normal);
}

bool nativeStageMode() {
  return HybridData.x == 1.0;
}

bool insideNativeWindow(vec3 p, float tolerance) {
  p -= WindowOrigin;
  return all(greaterThanEqual(p, NATIVE_WINDOW_LO - tolerance)) &&
         all(lessThanEqual(p, NATIVE_WINDOW_HI + tolerance));
}

vec2 nativeWindowInterval(vec3 origin, vec3 direction) {
  origin -= WindowOrigin;
  vec3 signedMinimum =
      mix(vec3(-1.0), vec3(1.0), greaterThanEqual(direction, vec3(0.0))) *
      max(abs(direction), vec3(1e-7));
  vec3 a = (NATIVE_WINDOW_LO - origin) / signedMinimum;
  vec3 b = (NATIVE_WINDOW_HI - origin) / signedMinimum;
  vec3 nearPlane = min(a, b), farPlane = max(a, b);
  return vec2(max(nearPlane.x, max(nearPlane.y, nearPlane.z)),
              min(farPlane.x, min(farPlane.y, farPlane.z)));
}

float sceneGeometryDistance(vec3 p) {
  if (Level > .5 && Level < 1.5)
    return joineryDistance(p);
  if (Level > 1.5)
    return ringsDistance(p);
  return HybridData.x > .5 ? stageDistance(p) : gravityDistance(p);
}

vec4 stoneSurfaceFinish(vec3 p, vec3 n, float footprint) {
  if (Level > 1.5)
    return ringsFinish(p, n, footprint);
  return stageSurfaceFinish(p, n, footprint);
}

float nativeRayDistance(float depth, vec2 uv) {
  return depth > 1e-8 ? length(nativeViewOffset(uv, depth)) : 1e7;
}

bool nativePixel(sampler2D depthSampler, vec2 uv) {
  ivec2 size = textureSize(depthSampler, 0);
  ivec2 pixel = clamp(ivec2(uv * vec2(size)), ivec2(0), size - 1);
  if (!nativeStageMode() || (pixel.y == size.y - 1 && pixel.x < PACKET_SIZE.x))
    return false;
  vec2 sampleUv = (vec2(pixel) + .5) / vec2(size);
  float depth = texelFetch(depthSampler, pixel, 0).r;
  if (depth <= 1e-8)
    return false;
  vec3 point = nativeWorldPoint(sampleUv, depth);
  if (!insideNativeWindow(point, .06))
    return false;
  if (Level > .5) {
    float distance = length(point - RayOrigin), hit;
    vec3 normal;
    return exactSceneTrace(RayOrigin, normalize(point - RayOrigin), distance + .04, hit,
                           normal) &&
           abs(hit - distance) < .04;
  }
  return true;
}

vec3 nativeDepthPoint(sampler2D depthSampler, ivec2 pixel) {
  ivec2 size = textureSize(depthSampler, 0);
  pixel = clamp(pixel, ivec2(0), size - 1);
  vec2 uv = (vec2(pixel) + .5) / vec2(size);
  return nativeWorldPoint(uv, max(texelFetch(depthSampler, pixel, 0).r, 1e-8));
}

vec3 nativeSurfaceNormal(sampler2D depthSampler, ivec2 pixel, out float ambient) {
  vec3 p = nativeDepthPoint(depthSampler, pixel);
  vec3 dx = nativeDepthPoint(depthSampler, pixel + ivec2(1, 0)) - p;
  vec3 previousX = p - nativeDepthPoint(depthSampler, pixel - ivec2(1, 0));
  vec3 dy = nativeDepthPoint(depthSampler, pixel + ivec2(0, 1)) - p;
  vec3 previousY = p - nativeDepthPoint(depthSampler, pixel - ivec2(0, 1));
  // Use the shorter edge at silhouettes to keep adjacent surfaces independent.
  if (dot(previousX, previousX) < dot(dx, dx))
    dx = previousX;
  if (dot(previousY, previousY) < dot(dy, dy))
    dy = previousY;
  vec3 normal = cross(dx, dy);
  ambient = 1.0;
  if (dot(normal, normal) < 1e-16)
    return normalize(RayOrigin - p);
  normal = normalize(normal);
  if (dot(normal, RayOrigin - p) < 0.0)
    normal = -normal;
  // Adjacent depth supplies contact shading around physical corners.
  float occlusion = 0.0;
  const ivec2 offsets[4] =
      ivec2[](ivec2(1, 0), ivec2(-1, 0), ivec2(0, 1), ivec2(0, -1));
  for (int i = 0; i < 4; i++) {
    vec3 sampleEdge = nativeDepthPoint(depthSampler, pixel + offsets[i] * 5) - p;
    float distance = length(sampleEdge);
    occlusion += max(0.0, dot(sampleEdge, normal)) / max(distance, .001) *
                 (1.0 - smoothstep(.12, .85, distance));
  }
  ambient = 1.0 - .26 * clamp(occlusion, 0.0, 1.0);
  return normal;
}

vec3 nativeSurfaceNormal(sampler2D depthSampler, ivec2 pixel) {
  float ambient;
  return nativeSurfaceNormal(depthSampler, pixel, ambient);
}
#endif
