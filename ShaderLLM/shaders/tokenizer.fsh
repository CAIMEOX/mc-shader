#version 330
#extension GL_ARB_separate_shader_objects : require
uniform sampler2D PacketSampler, UnicodeMetaSampler, UnicodeNfdSampler,
    UnicodeComposeSampler, SpecialMetaSampler, SpecialCharsSampler, MergesSampler;
layout(location = 0) out vec4 fragColor;
#include <qwen:codec.glsl>
#include <qwen:tokenizer_constants.glsl>
int cp[512], classes[512], symbols[512], segments[512], links[512];
int cpCount, byteCount, errorCode;
uint hashPair(uint a, uint b) {
  return a * 0x9e3779b1u ^ b * 0x85ebca6bu;
}
int flags(int c) {
  return int(integer(UnicodeMetaSampler, c * 3));
}
int cc(int c) {
  return flags(c) >> 8;
}
int composition(int a, int b) {
  if (a >= 0x1100 && a < 0x1113 && b >= 0x1161 && b < 0x1176)
    return 0xac00 + (a - 0x1100) * 588 + (b - 0x1161) * 28;
  if (a >= 0xac00 && a <= 0xd7a3 && (a - 0xac00) % 28 == 0 && b > 0x11a7 && b < 0x11c3)
    return a + b - 0x11a7;
  uint slot = hashPair(uint(a), uint(b)) & 65535u;
  for (int j = 0; j < COMPOSE_PROBES; j++) {
    int base = int(slot) * 4;
    uint left = integer(UnicodeComposeSampler, base);
    if (left == 0xffffffffu)
      return -1;
    if (left == uint(a) && integer(UnicodeComposeSampler, base + 1) == uint(b))
      return int(integer(UnicodeComposeSampler, base + 2));
    slot = (slot + 1u) & 65535u;
  }
  return -1;
}
void nfd(int c) {
  int base = c * 3, start = int(integer(UnicodeMetaSampler, base + 1)),
      n = int(integer(UnicodeMetaSampler, base + 2));
  for (int j = 0; j < n; j++) {
    if (cpCount >= 512) {
      errorCode = 1;
      return;
    }
    int part = int(integer(UnicodeNfdSampler, start + j)), cl = cc(part), p = cpCount;
    while (cl != 0 && p > 0 && classes[p - 1] > cl) {
      cp[p] = cp[p - 1];
      classes[p] = classes[p - 1];
      p--;
    }
    cp[p] = part;
    classes[p] = cl;
    cpCount++;
  }
}
void normalize() {
  int count = cpCount, outCount = 0, starter = -1, lastClass = 0;
  for (int j = 0; j < count; j++) {
    int c = cp[j], cl = classes[j], merged = -1;
    if (starter >= 0 && (lastClass < cl || lastClass == 0))
      merged = composition(cp[starter], c);
    if (merged >= 0)
      cp[starter] = merged;
    else {
      if (cl == 0)
        starter = outCount;
      cp[outCount++] = c;
      lastClass = cl;
    }
  }
  cpCount = outCount;
}
int special(int p, out int length) {
  for (int i = 0; i < SPECIAL_COUNT; i++) {
    int base = i * 3, start = int(integer(SpecialMetaSampler, base + 1)),
        n = int(integer(SpecialMetaSampler, base + 2));
    if (p + n > cpCount)
      continue;
    bool equal = true;
    for (int j = 0; j < n; j++)
      if (cp[p + j] != int(integer(SpecialCharsSampler, start + j))) {
        equal = false;
        break;
      }
    if (equal) {
      length = n;
      return int(integer(SpecialMetaSampler, base));
    }
  }
  length = 0;
  return -1;
}
int category(int p) {
  return flags(cp[p]) & 255;
}
bool letter(int p) {
  return p < cpCount && (category(p) & 2) != 0;
}
bool number(int p) {
  return p < cpCount && (category(p) & 4) != 0;
}
bool space(int p) {
  return p < cpCount && (category(p) & 1) != 0;
}
bool newline(int p) {
  return p < cpCount && (category(p) & 8) != 0;
}
bool punctuation(int p) {
  return p < cpCount && (category(p) & 7) == 0;
}
int lower(int c) {
  return c >= 65 && c <= 90 ? c + 32 : c;
}
int chunkEnd(int p, int end) {
  if (cp[p] == 39 && p + 1 < end) {
    int a = lower(cp[p + 1]);
    if (a == 115 || a == 116 || a == 109 || a == 100)
      return p + 2;
    if (p + 2 < end) {
      int b = lower(cp[p + 2]);
      if ((a == 114 && b == 101) || (a == 118 && b == 101) || (a == 108 && b == 108))
        return p + 3;
    }
  }
  int q = p;
  if (!letter(q) && !number(q) && !newline(q))
    q++;
  if (q < end && letter(q)) {
    while (q < end && letter(q))
      q++;
    return q;
  }
  if (number(p))
    return p + 1;
  q = p;
  if (cp[q] == 32)
    q++;
  if (q < end && punctuation(q)) {
    while (q < end && punctuation(q))
      q++;
    while (q < end && newline(q))
      q++;
    return q;
  }
  if (space(p)) {
    q = p;
    int lastNewline = -1;
    while (q < end && space(q)) {
      if (newline(q))
        lastNewline = q;
      q++;
    }
    if (lastNewline >= 0)
      return lastNewline + 1;
    if (q == end)
      return q;
    if (q - p > 1)
      return q - 1;
    return q;
  }
  return p + 1;
}
void appendSymbol(int id, int segment) {
  if (byteCount >= 512) {
    errorCode = 2;
    return;
  }
  symbols[byteCount] = id;
  segments[byteCount] = segment;
  links[byteCount] = byteCount + 1;
  byteCount++;
}
void utf8(int c, int segment) {
  if (c < 128)
    appendSymbol(BYTE_IDS[c], segment);
  else if (c < 2048) {
    appendSymbol(BYTE_IDS[192 | (c >> 6)], segment);
    appendSymbol(BYTE_IDS[128 | (c & 63)], segment);
  } else if (c < 65536) {
    appendSymbol(BYTE_IDS[224 | (c >> 12)], segment);
    appendSymbol(BYTE_IDS[128 | ((c >> 6) & 63)], segment);
    appendSymbol(BYTE_IDS[128 | (c & 63)], segment);
  } else {
    appendSymbol(BYTE_IDS[240 | (c >> 18)], segment);
    appendSymbol(BYTE_IDS[128 | ((c >> 12) & 63)], segment);
    appendSymbol(BYTE_IDS[128 | ((c >> 6) & 63)], segment);
    appendSymbol(BYTE_IDS[128 | (c & 63)], segment);
  }
}
uvec2 merge(int a, int b) {
  uint slot = hashPair(uint(a), uint(b)) & 524287u;
  for (int j = 0; j < MERGE_PROBES; j++) {
    int base = int(slot) * 4;
    uint left = integer(MergesSampler, base);
    if (left == 0xffffffffu)
      break;
    if (left == uint(a) && integer(MergesSampler, base + 1) == uint(b))
      return uvec2(integer(MergesSampler, base + 2), integer(MergesSampler, base + 3));
    slot = (slot + 1u) & 524287u;
  }
  return uvec2(0xffffffffu);
}
void main() {
  int resultIndex = int(gl_FragCoord.x), length = int(integer(PacketSampler, 1));
  errorCode = 0;
  cpCount = 0;
  byteCount = 0;
  if (length < 0 || length > 128) {
    fragColor = packU(resultIndex == 1 ? 3u : 0u);
    return;
  }
  for (int i = 0; i < PREFIX_LENGTH; i++)
    nfd(PREFIX[i]);
  for (int i = 0; i < length; i++)
    nfd(int(integer(PacketSampler, 3 + i)));
  for (int i = 0; i < SUFFIX_LENGTH; i++)
    nfd(SUFFIX[i]);
  normalize();
  int p = 0, segment = 0;
  while (p < cpCount && errorCode == 0) {
    int len, id = special(p, len);
    if (id >= 0) {
      appendSymbol(id, segment++);
      p += len;
      continue;
    }
    int end = p + 1;
    while (end < cpCount) {
      int ignored;
      if (special(end, ignored) >= 0)
        break;
      end++;
    }
    while (p < end) {
      int next = chunkEnd(p, end);
      for (int j = p; j < next; j++)
        utf8(cp[j], segment);
      segment++;
      p = next;
    }
  }
  for (int iter = 0; iter < 512 && errorCode == 0; iter++) {
    uint rank = 0xffffffffu;
    int chosen = -1, newId = 0;
    for (int j = 0; j < byteCount; j++) {
      if (symbols[j] < 0 || links[j] >= byteCount)
        continue;
      int right = links[j];
      if (segments[j] != segments[right])
        continue;
      uvec2 candidate = merge(symbols[j], symbols[right]);
      if (candidate.y < rank) {
        rank = candidate.y;
        chosen = j;
        newId = int(candidate.x);
      }
    }
    if (chosen < 0)
      break;
    int right = links[chosen];
    symbols[chosen] = newId;
    links[chosen] = links[right];
    symbols[right] = -1;
  }
  int count = 0, token = 0;
  for (int j = 0; j < byteCount; j++)
    if (symbols[j] >= 0) {
      if (count == resultIndex - 2)
        token = symbols[j];
      count++;
    }
  if (count > 128)
    errorCode = 4;
  fragColor =
      packU(resultIndex == 0 ? uint(count)
                             : (resultIndex == 1 ? uint(errorCode) : uint(token)));
}
