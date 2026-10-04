#ifndef ESCHER_PACKET
#define ESCHER_PACKET
#include <escher:settings.glsl>
#include <escher:codec.glsl>
uint packetWord(sampler2D packet, int index) {
  return rgbWord(texelFetch(packet, ivec2(index, 0), 0).rgb);
}
uint bits(sampler2D packet, int offset, int width) {
  uint value = 0u;
  int consumed = 0;
  for (int part = 0; part < 3 && consumed < width; part++) {
    int bit = offset + consumed, shift = bit % 24,
        count = min(width - consumed, 24 - shift);
    value |=
        ((packetWord(packet, 5 + bit / 24) >> uint(shift)) & ((1u << uint(count)) - 1u))
        << uint(consumed);
    consumed += count;
  }
  return value;
}
bool presentPacket(sampler2D packet) {
  return texelFetch(packet, ivec2(0), 0).a > .5 && packetWord(packet, 0) == MAGIC &&
         (packetWord(packet, 2) & 1u) == 1u && bits(packet, FIELD_PERIOD, 8) > 0u;
}
bool validPacket(sampler2D packet) {
  return presentPacket(packet) && bits(packet, FIELD_ENABLED, 1) == 1u;
}
ivec3 regionOrigin(sampler2D p) {
  return ivec3(int(bits(p, FIELD_ORIGIN_X, 26)) - 33554432,
               int(bits(p, FIELD_ORIGIN_Y, 12)) - 2048,
               int(bits(p, FIELD_ORIGIN_Z, 26)) - 33554432);
}
#endif
