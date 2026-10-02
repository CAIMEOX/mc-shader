
int h = i / HEAD_DIM, j = i % HEAD_DIM;
for (int t = 0; t <= State.y; t++)
  outValue += scalar(Input0Sampler, h *CONTEXT_SIZE + t) *
              scalar(ValuesSampler, (State.z * CONTEXT_SIZE + t) * KV_SIZE +
                                        (h / KV_MULTIPLIER) * HEAD_DIM + j);
