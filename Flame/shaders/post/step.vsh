#version 330
#extension GL_ARB_separate_shader_objects : require
#include <flame:codec.glsl>
uniform sampler2D ControlSampler;
layout(std140) uniform Parameters {
  vec4 Values;
};
void main() {
  uint steps = decodeUint(texelFetch(ControlSampler, ivec2(3, 0), 0));
  bool execute = Values.y < .5 ? steps > uint(Values.x)
                 : Values.y < 1.5
                     ? steps == 1u
                     : decodeUint(texelFetch(ControlSampler, ivec2(5, 0), 0)) != 0u;
  vec2 uv = vec2((gl_VertexIndex << 1) & 2, gl_VertexIndex & 2);
  gl_Position = execute ? vec4(uv * 2.0 - 1.0, 0, 1) : vec4(2, 2, 0, 1);
}
