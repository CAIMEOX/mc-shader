// quantized embedding
uint offset = (uint(State.x) * uint(n / 64) + uint(i / 64)) * 17u;
ivec4 q = ivec4(round(weight(offset + uint((i % 64) / 4)) * 255.)) - 128;
outValue = float(q[i % 4]) * unpackF(weight(offset + 16u));
