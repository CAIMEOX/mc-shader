
int t = i % CONTEXT_SIZE, h = i / CONTEXT_SIZE;
if (t > State.y)
  discard;
for (int j = 0; j < HEAD_DIM; j++)
  outValue += scalar(Input0Sampler, h *HEAD_DIM + j) *
              scalar(KeysSampler, (State.z * CONTEXT_SIZE + t) * KV_SIZE +
                                      (h / KV_MULTIPLIER) * HEAD_DIM + j);
outValue *= inversesqrt(float(HEAD_DIM));
