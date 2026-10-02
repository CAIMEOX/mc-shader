int nextCodepoint(sampler2D outputData, inout int pos, int count) {
  uint a = integer(outputData, pos++);
  int code = int(a), n = 0;
  if (a >= 240u) {
    code = int(a & 7u);
    n = 3;
  } else if (a >= 224u) {
    code = int(a & 15u);
    n = 2;
  } else if (a >= 192u) {
    code = int(a & 31u);
    n = 1;
  }
  if (pos + n > count) {
    pos = count;
    return -1;
  }
  for (int k = 0; k < n; k++)
    code = (code << 6) | int(integer(outputData, pos++) & 63u);
  return code;
}
