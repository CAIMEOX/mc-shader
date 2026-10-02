// stable softmax statistics
int h = i / 2;
float m = -1e30;
for (int t = 0; t <= State.y; t++)
  m = max(m, scalar(Input0Sampler, h *CONTEXT_SIZE + t));
if (i % 2 == 0)
  outValue = m;
else
  for (int t = 0; t <= State.y; t++)
    outValue += exp(scalar(Input0Sampler, h *CONTEXT_SIZE + t) - m);
