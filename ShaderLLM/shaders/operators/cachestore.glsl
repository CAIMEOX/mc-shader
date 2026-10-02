// row cache store, remaining texels untouched
int row = State.z * CONTEXT_SIZE + State.y;
if (i / KV_SIZE != row)
  discard;
outValue = scalar(Input0Sampler, i % KV_SIZE);
