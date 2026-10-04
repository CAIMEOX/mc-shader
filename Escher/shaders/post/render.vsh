#version 330
#extension GL_ARB_separate_shader_objects : require
#include <minecraft:globals.glsl>
uniform sampler2D PacketSampler;
uniform sampler2D FrameSampler;
#define ESCHER_RENDER_VERTEX
#include <escher:render_data.glsl>
#include <escher:folding_space.glsl>
void main() {
  vec2 uv = vec2((gl_VertexIndex << 1) & 2, gl_VertexIndex & 2);
  gl_Position = vec4(uv * 2.0 - 1.0, 0, 1);
  texCoord = uv;
  FrameReady = validPacket(PacketSampler) ? 1.0 : 0.0;
  RenderQuality = float(bits(PacketSampler, FIELD_QUALITY, 2));
  RayOrigin = vec3(CameraBlockPos - regionOrigin(PacketSampler)) - CameraOffset;
  float period = max(1.0, float(bits(PacketSampler, FIELD_PERIOD, 8)));
  float logarithm =
      log(clamp(float(bits(PacketSampler, FIELD_RATIO, 10)) / 1024.0, .5, .981));
  Lens = vec4(period, logarithm,
              (float(bits(PacketSampler, FIELD_TURN, 13)) - 4096.0) / 1024.0,
              -period / logarithm);
  // Only the render coordinate is folded. Native motion retains its sub-block
  // precision.
  RayOrigin.z = mod(RayOrigin.z, period);
  vec4 q =
      decodeRotation(uvec2(packetWord(PacketSampler, 1), packetWord(PacketSampler, 2)));
  InverseView =
      transpose(mat3(rotateVector(q, vec3(1, 0, 0)), rotateVector(q, vec3(0, 1, 0)),
                     rotateVector(q, vec3(0, 0, 1))));
  float scale = decodeFloat24(packetWord(PacketSampler, 3));
  Projection = vec2(scale * ScreenSize.y / ScreenSize.x, scale);
  FoldingData = vec4(float(bits(PacketSampler, FIELD_SCENE, 1)),
                     decodeFloat(texelFetch(FrameSampler, ivec2(0, 0), 0)),
                     decodeFloat(texelFetch(FrameSampler, ivec2(2, 0), 0)),
                     decodeFloat(texelFetch(FrameSampler, ivec2(7, 0), 0)));
  vec3 source = foldSourceCamera(RayOrigin, period);
  FoldingEye = foldPoint(source, FoldingData.y);
  FoldingSideRoll = decodeFloat(texelFetch(FrameSampler, ivec2(8, 0), 0));
  FoldingScale = foldScale(source, FoldingData.y);
  mat3 axis = mat3(vec3(0, 0, -1), vec3(0, 1, 0), vec3(1, 0, 0));
  FoldingView = foldFrame(source, FoldingData.y) * axis * InverseView;
  FoldingLight = foldFrame(source, FoldingData.y) * normalize(vec3(-.5, .85, -.4));
  if (bits(PacketSampler, FIELD_OVERVIEW, 1) == 1u) {
    float pitch = .37 * (1. - FoldingData.y), yaw = .52 - .4 * FoldingData.y;
    mat3 pitchFrame = mat3(vec3(1, 0, 0), vec3(0, cos(pitch), -sin(pitch)),
                           vec3(0, sin(pitch), cos(pitch)));
    mat3 yawFrame =
        mat3(vec3(cos(yaw), 0, -sin(yaw)), vec3(0, 1, 0), vec3(sin(yaw), 0, cos(yaw)));
    FoldingView = yawFrame * pitchFrame *
                  mat3(vec3(-1, 0, 0), vec3(0, 1, 0), vec3(0, 0, -1)) * InverseView;
    vec3 center = mix(vec3(0, 1.3, 0), vec3(0, -FOLD_RADIUS, 0), FoldingData.y);
    FoldingEye = center - FoldingView * vec3(0, 0, -1) * mix(50., 48., FoldingData.y);
    FoldingScale = 1.;
    FoldingLight = normalize(vec3(-.4, .8, 1.));
  }
}
