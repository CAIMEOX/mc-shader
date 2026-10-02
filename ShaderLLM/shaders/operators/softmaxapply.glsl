
int t = i % CONTEXT_SIZE, h = i / CONTEXT_SIZE;
if (t > State.y)
  discard;
outValue = exp(scalar(Input0Sampler, i) - scalar(Input1Sampler, h * 2)) /
           scalar(Input1Sampler, h * 2 + 1);
