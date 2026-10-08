#version 330
#extension GL_ARB_separate_shader_objects : require
#include <backrooms:render_data.glsl>
#include <backrooms:scene.glsl>
layout(location = 0) out vec4 fragColor;
void main() {
  int i = int(gl_FragCoord.x);
  float value = 0.0;
  if (i == 0)
    value = FrameReady;
  else if (i == 1)
    value = RoomId;
  else if (i == 2)
    value = MirrorState;
  else if (i < 6)
    value = RayOrigin[i - 3];
  else if (i == 6)
    value = Projection.y;
  else if (i == 7)
    value = DepthProjection.y;
  else {
    int fixture = (i - 8) / 4, component = (i - 8) % 4;
    Hit h = traceSpace(FIXTURE_ORIGIN[fixture], FIXTURE_DIRECTION[fixture],
                       FIXTURE_ROOM[fixture]);
    value = component == 0   ? h.t
            : component == 1 ? float(h.material)
            : component == 2 ? float(h.room)
                             : float(h.primary);
  }
  fragColor = encodeFloat(value);
}
