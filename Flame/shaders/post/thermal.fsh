#version 330
#extension GL_ARB_separate_shader_objects : require
#include <flame:step.glsl>
#include <flame:packet.glsl>
uniform sampler2D PacketSampler;
uniform sampler2D PreviousSampler;
uniform sampler2D GasSampler;
layout(location = 0) out vec4 fragColor;
float radianceAt(ivec3 p) {
  float temperature = gasAt(GasSampler, p, 0), reaction = gasAt(GasSampler, p, 4);
  return clamp(reaction / .06, 0.0, 1.0) *
         pow(clamp((temperature - AMBIENT) / 1400.0, 0.0, 1.4), 4.0);
}
float incidentRadiation(ivec3 p) {
  float incident = 0.0;
  for (int face = 0; face < 3; face++)
    for (int side = -1; side <= 1; side += 2) {
      ivec3 origin = p + axisVector(face) * side;
      if (solidAt(origin))
        continue;
      incident = max(incident, radianceAt(origin));
      for (int tangent = 0; tangent < 3; tangent++)
        if (tangent != face)
          for (int sign = -1; sign <= 1; sign += 2) {
            ivec3 q = origin;
            for (int distance = 1; distance <= 4; distance++) {
              q += axisVector(tangent) * sign;
              if (!inGrid(q) || solidAt(q))
                break;
              incident = max(incident,
                             radianceAt(q) / (1.0 + .65 * float(distance * distance)));
            }
          }
    }
  return incident;
}
void main() {
  int index = fragmentIndex(), kind = index / CELLS;
  ivec3 p = gridCell(index % CELLS);
  if (!solidAt(p)) {
    fragColor = encodeFloat(kind == 1 ? AMBIENT : 0.0);
    return;
  }
  int material = materialAt(p);
  float fuel = resetStep() ? initialFuel(p) : stored(PreviousSampler, p, 0);
  float heat = resetStep() ? AMBIENT : stored(PreviousSampler, p, 1), released = 0.0;
  if (quenching(PacketSampler))
    heat = AMBIENT;
  else {
    float numerator = heat + DT * .08 * AMBIENT, denominator = 1.0 + DT * .08;
    for (int a = 0; a < 3; a++)
      for (int s = -1; s <= 1; s += 2) {
        ivec3 q = p + axisVector(a) * s;
        float coefficient, other;
        if (solidAt(q)) {
          coefficient = material > 0 && materialAt(q) > 0 ? 1.2 : .035;
          other = resetStep() || !inGrid(q) ? AMBIENT : stored(PreviousSampler, q, 1);
        } else {
          coefficient = material > 0 ? .75 : .12;
          other = gasAt(GasSampler, q, 0);
        }
        numerator += DT * coefficient * other;
        denominator += DT * coefficient;
      }
    if (sourceEnabled(PacketSampler)) {
      vec3 d = (vec3(p - gridCell(sourceIndex(PacketSampler)))) * CELL_SIZE;
      numerator += DT * ignitionPower(PacketSampler) * 1300.0 * exp(-dot(d, d) / .55);
    }
    if (material > 0 && exposureAt(p) > 0.0)
      numerator += DT * 1200.0 * incidentRadiation(p);
    heat = clamp(numerator / denominator, AMBIENT, 1800.0);
    if (fuel > 0.0 && material > 0 && exposureAt(p) > 0.0) {
      float activation =
          smoothstep(PYROLYSIS_T[material], PYROLYSIS_T[material] + 190.0, heat);
      released = min(fuel, DT * PYROLYSIS_RATE[material] * activation *
                               pow(clamp(fuel / FUEL_LOAD[material], 0.0, 1.0), .25));
      fuel -= released;
      heat = max(AMBIENT, heat - released * 170.0);
    }
  }
  fragColor = encodeFloat(kind == 0 ? fuel : kind == 1 ? heat : released / DT);
}
