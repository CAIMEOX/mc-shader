#version 330
#extension GL_ARB_separate_shader_objects : require
#include <flame:step.glsl>
#include <flame:packet.glsl>
uniform sampler2D PacketSampler;
uniform sampler2D PreviousSampler;
uniform sampler2D ThermalSampler;
layout(location = 0) out vec4 fragColor;
void main() {
  int i = fragmentIndex(), kind = i / CELLS;
  ivec3 p = gridCell(i % CELLS);
  if (solidAt(p)) {
    fragColor = encodeFloat(ambientGas(kind));
    return;
  }
  float temperature = stored(PreviousSampler, p, 0),
        vapor = stored(PreviousSampler, p, 1), smoke = stored(PreviousSampler, p, 2),
        oxygen = stored(PreviousSampler, p, 3);
  float injected = 0, hot = 0;
  for (int a = 0; a < 3; a++)
    for (int s = -1; s <= 1; s += 2) {
      ivec3 q = p + axisVector(a) * s;
      if (inGrid(q) && solidAt(q) && exposureAt(q) > 0.0) {
        float mass = DT * stored(ThermalSampler, q, 2) / exposureAt(q);
        injected += mass;
        hot += mass * stored(ThermalSampler, q, 1);
      }
    }
  vapor += injected;
  temperature = (temperature + hot * 3.0) / (1.0 + injected * 3.0);
  if (sourceEnabled(PacketSampler)) {
    vec3 d = (vec3(p - gridCell(sourceIndex(PacketSampler)))) * CELL_SIZE;
    temperature += DT * ignitionPower(PacketSampler) * 1600.0 * exp(-dot(d, d) / .55);
  }
  float burn = 0;
  if (quenching(PacketSampler)) {
    temperature = AMBIENT;
    vapor = 0;
    oxygen = 1;
    smoke *= exp(-1.2 * DT);
  } else {
    float ignition = smoothstep(470.0, 680.0, temperature);
    burn = min(min(vapor, oxygen / 3.0), vapor * (1.0 - exp(-5.0 * ignition * DT)));
    vapor -= burn;
    oxygen -= 3.0 * burn;
    temperature += burn * 42000.0;
    smoke += burn * 6.0;
    temperature = AMBIENT + (temperature - AMBIENT) * exp(-.55 * DT);
    vapor *= exp(-.035 * DT);
    smoke *= exp(-.10 * DT);
  }
  float result = kind == 0   ? clamp(temperature, AMBIENT, 2300.0)
                 : kind == 1 ? clamp(vapor, 0.0, 2.0)
                 : kind == 2 ? clamp(smoke, 0.0, 4.0)
                 : kind == 3 ? clamp(oxygen, 0.0, 1.0)
                             : burn / DT;
  fragColor = encodeFloat(result);
}
