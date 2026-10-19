#ifndef MANIFOLD_PACKET
#define MANIFOLD_PACKET
#include <manifold:settings.glsl>
#include <manifold:codec.glsl>
uint packetWordAt(sampler2D packet, ivec2 origin, int index) {
  return rgbWord(texelFetch(packet, origin + ivec2(index, 0), 0).rgb);
}
uint packetWord(sampler2D packet, int index) {
  return packetWordAt(packet, ivec2(0), index);
}
uint bitsAt(sampler2D packet, ivec2 origin, int offset, int width) {
  uint value = 0u;
  int consumed = 0;
  for (int part = 0; part < 3 && consumed < width; part++) {
    int bit = offset + consumed, shift = bit % 24;
    int count = min(width - consumed, 24 - shift);
    value |= ((packetWordAt(packet, origin, 22 + bit / 24) >> uint(shift)) &
              ((1u << uint(count)) - 1u))
             << uint(consumed);
    consumed += count;
  }
  return value;
}
uint bits(sampler2D packet, int offset, int width) {
  return bitsAt(packet, ivec2(0), offset, width);
}
bool presentPacketAt(sampler2D packet, ivec2 origin) {
  bool bank = bitsAt(packet, origin, FIELD_H_LEVEL, 2) == 0u ||
              (packetWordAt(packet, origin, OBJECT_WORD_OFFSET + OBJECT_COUNT + 1) ==
                   OBJECT_MAGIC &&
               packetWordAt(packet, origin, OBJECT_WORD_OFFSET + OBJECT_COUNT + 2) ==
                   bitsAt(packet, origin, FIELD_R_REVISION, 16));
  return bank && texelFetch(packet, origin, 0).a > .5 &&
         packetWordAt(packet, origin, 0) == MAGIC &&
         (packetWordAt(packet, origin, 2) & 1u) == 1u &&
         (bitsAt(packet, origin, FIELD_PERIOD, 8) == 32u ||
          bitsAt(packet, origin, FIELD_PERIOD, 8) == 64u);
}
bool presentPacket(sampler2D packet) {
  return presentPacketAt(packet, ivec2(0));
}
bool validPacket(sampler2D packet) {
  return presentPacket(packet) && bits(packet, FIELD_ENABLED, 1) == 1u;
}
#endif
