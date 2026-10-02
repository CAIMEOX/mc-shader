#ifndef FLAME_PACKET
#define FLAME_PACKET
#include <flame:settings.glsl>
#include <flame:codec.glsl>
uint packetWord(sampler2D packet, int index) {
  return rgbWord(texelFetch(packet, ivec2(index % 32, index / 32), 0).rgb);
}
uint packetBits(sampler2D packet, int firstWord, int offset, int width) {
  uint value = 0u;
  int consumed = 0;
  for (int part = 0; part < 3 && consumed < width; part++) {
    int bit = offset + consumed, shift = bit % 24,
        count = min(width - consumed, 24 - shift);
    uint fragment = (packetWord(packet, firstWord + bit / 24) >> uint(shift)) &
                    ((1u << uint(count)) - 1u);
    value |= fragment << uint(consumed);
    consumed += count;
  }
  return value;
}
bool validPacket(sampler2D packet) {
  float scale = decodeFloat24(packetWord(packet, 3)),
        depth = decodeFloat24(packetWord(packet, 4));
  return texelFetch(packet, ivec2(0), 0).a > .5 && packetWord(packet, 0) == MAGIC &&
         packetWord(packet, 5) > 0u && (packetWord(packet, 2) & 1u) == 1u &&
         scale > .05 && scale < 100.0 && depth >= 0.0 && depth < .1;
}
ivec3 regionOrigin(sampler2D packet) {
  return ivec3(int(packetBits(packet, 5, FIELD_ORIGIN_X, 26)) - 33554432,
               int(packetBits(packet, 5, FIELD_ORIGIN_Y, 12)) - 2048,
               int(packetBits(packet, 5, FIELD_ORIGIN_Z, 26)) - 33554432);
}
int sourceIndex(sampler2D packet) {
  return int(packetBits(packet, 5, FIELD_SOURCE, 14));
}
float ignitionPower(sampler2D packet) {
  return float(packetBits(packet, 5, FIELD_POWER, 9)) / 64.0;
}
uint flameMode(sampler2D packet) {
  return packetBits(packet, 5, FIELD_MODE, 2);
}
bool sourceEnabled(sampler2D packet) {
  return flameMode(packet) == 1u;
}
bool quenching(sampler2D packet) {
  return flameMode(packet) == 2u;
}
#endif
